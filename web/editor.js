// Copyright (c) 2026 Eirini Konidari. All rights reserved.
/* Netherlanded Editor Panel.
   Prototype 6-tab workflow (To check, Local texts, Services, Figures, Steps, Changes)
   enforcing can_edit_city() shared-city locks, URL validation, change reasons,
   and optional live /api/editor synchronization via Staff Bearer JWT.
   No third-party scripts, no HTML injection, Object.create(null) maps. */
(function () {
  'use strict';

  var DAY = 86400000;
  var STALE = 180;
  var TIMEOUT_MS = 10000;
  var FALLBACK_ENDPOINT = '/api/editor';
  var STAFF_TOKEN_KEY = 'nl-staff-jwt';
  var STORAGE_KEY = 'nl-editor-v2';

  var DEFAULT_BANNER_PREFIX = 'Prototype & live-ready editor. ';
  var DEFAULT_BANNER_BODY = 'Shared cities (The Hague, Delft) enforce can_edit_city(): institutional offices create scoped overrides rather than overwriting shared municipal text, while single-school cities (Zoetermeer) are directly editable.';

  var rawTag = document.getElementById('content');
  var C = { facts: {}, institutions: [], municipalities: [], services: [], step_local: [], steps: [] };
  try {
    if (rawTag && rawTag.textContent) {
      C = JSON.parse(rawTag.textContent);
    }
  } catch (_) {}

  var MUNI = Object.create(null);
  (C.municipalities || []).forEach(function (m) { MUNI[m.id] = m; });
  var STEP = Object.create(null);
  (C.steps || []).forEach(function (s) { STEP[s.id] = s; });
  var INST_BY_ID = Object.create(null);
  var CITY_PARENTS = Object.create(null);
  (C.institutions || []).forEach(function (inst) {
    INST_BY_ID[inst.id] = inst;
    var parentId = inst.campus_of || inst.id;
    var cityId = inst.city_id;
    if (cityId) {
      if (!CITY_PARENTS[cityId]) { CITY_PARENTS[cityId] = Object.create(null); }
      CITY_PARENTS[cityId][parentId] = true;
    }
  });
  var DEMO_SHARED_CITIES = Object.create(null);
  Object.keys(CITY_PARENTS).forEach(function (cityId) {
    if (Object.keys(CITY_PARENTS[cityId]).length > 1) {
      DEMO_SHARED_CITIES[cityId] = true;
    }
  });

  function todayIso() {
    var d = new Date();
    return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
  }

  var TODAY = todayIso();

  var studyCities = (C.municipalities || []).filter(function (m) { return m.is_study_city; }).map(function (m) { return m.id; });
  var ROLES = Object.create(null);
  ROLES.thuas = {
    name: 'THUAS International Office',
    cities: ['the-hague', 'delft', 'zoetermeer'],
    inst: ['thuas', 'thuas-delft', 'thuas-zoetermeer'],
    all: false
  };
  ROLES.admin = {
    name: 'Project team (super_admin)',
    cities: studyCities,
    inst: [],
    all: true
  };

  var E = {
    mode: 'demo',
    login: 'thuas',
    tab: 'check',
    city: 'the-hague',
    svcType: '',
    open: null,
    formErr: '',
    showAllCheck: false,
    publishing: false,
    pending: [],
    published: [],
    facts: Object.create(null),
    services: Object.create(null),
    added: [],
    local: Object.create(null),
    addedLocal: [],
    steps: Object.create(null),
    checked: Object.create(null),
    liveData: null
  };

  var ALLOWED_SUBPATHS = Object.create(null);
  ALLOWED_SUBPATHS['/service'] = true;
  ALLOWED_SUBPATHS['/step-local'] = true;
  ALLOWED_SUBPATHS['/fact'] = true;
  ALLOWED_SUBPATHS['/verify'] = true;

  function toNullMap(obj) {
    var out = Object.create(null);
    if (obj && typeof obj === 'object' && !Array.isArray(obj)) {
      Object.keys(obj).forEach(function (k) { out[k] = obj[k]; });
    }
    return out;
  }

  try {
    var saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || 'null');
    if (saved && saved.pending && ROLES[saved.login]) {
      E.login = saved.login;
      E.tab = saved.tab || 'check';
      E.city = saved.city || 'the-hague';
      E.pending = Array.isArray(saved.pending) ? saved.pending : [];
      E.published = Array.isArray(saved.published) ? saved.published : [];
      E.facts = toNullMap(saved.facts);
      E.services = toNullMap(saved.services);
      E.added = Array.isArray(saved.added) ? saved.added : [];
      E.local = toNullMap(saved.local);
      E.addedLocal = Array.isArray(saved.addedLocal) ? saved.addedLocal : [];
      E.steps = toNullMap(saved.steps);
      E.checked = toNullMap(saved.checked);
    }
  } catch (_) {}

  function keep() {
    if (E.mode === 'live') { return; }
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify({
        login: E.login,
        tab: E.tab,
        city: E.city,
        pending: E.pending,
        published: E.published,
        facts: E.facts,
        services: E.services,
        added: E.added,
        local: E.local,
        addedLocal: E.addedLocal,
        steps: E.steps,
        checked: E.checked
      }));
    } catch (_) {}
  }

  function make(tag, className, text) {
    var el = document.createElement(tag);
    if (className) { el.className = className; }
    if (text !== undefined && text !== null) { el.textContent = String(text); }
    return el;
  }

  function clearChildren(node) {
    while (node && node.firstChild) { node.removeChild(node.firstChild); }
  }

  function role() {
    if (E.mode === 'live' && E.liveData && E.liveData.meta) {
      var m = E.liveData.meta;
      var isAll = m.role === 'super_admin';
      var instId = m.institution_id || '';
      var cities;
      if (isAll) {
        cities = studyCities.slice();
        (m.campus_cities || []).forEach(function (c) {
          if (cities.indexOf(c) === -1 && (!MUNI[c] || MUNI[c].is_study_city)) {
            cities.push(c);
          }
        });
      } else {
        var rawCities = (Array.isArray(m.campus_cities) && m.campus_cities.length) ? m.campus_cities : (m.editable_cities || []);
        cities = rawCities.filter(function (c) { return !MUNI[c] || MUNI[c].is_study_city; });
        if (!cities.length && instId) {
          cities = (C.institutions || []).filter(function (i) {
            return (i.id === instId || i.campus_of === instId) && i.city_id;
          }).map(function (i) { return i.city_id; });
        }
      }
      var instList = [];
      if (!isAll && instId) {
        instList.push(instId);
        (C.institutions || []).forEach(function (i) {
          if (i.campus_of === instId && instList.indexOf(i.id) === -1) { instList.push(i.id); }
        });
      }
      var rName = isAll
        ? 'Project team (super_admin)'
        : ((INST_BY_ID[instId] && INST_BY_ID[instId].name) || (instId ? instId.toUpperCase() + ' Office' : 'Staff editor'));
      return { name: rName, cities: cities, inst: instList, all: isAll };
    }
    return ROLES[E.login] || ROLES.thuas;
  }

  function instLabel() {
    var r = role();
    return r.inst && r.inst[0] ? r.inst[0].toUpperCase() : 'institution';
  }

  function areaOf(c) {
    return (C.municipalities || [])
      .filter(function (m) { return m.id === c || (m.near_city_id === c && !m.is_study_city); })
      .map(function (m) { return m.id; });
  }

  function fileOf(m) {
    if (!m) { return 'core'; }
    var muni = MUNI[m];
    var base = (muni && !muni.is_study_city && muni.near_city_id) ? muni.near_city_id : m;
    return 'city-' + base;
  }

  function isSharedCity(muniId) {
    var studyParent = (MUNI[muniId] && !MUNI[muniId].is_study_city && MUNI[muniId].near_city_id)
      ? MUNI[muniId].near_city_id
      : muniId;
    if (E.mode === 'live' && E.liveData && E.liveData.meta && Array.isArray(E.liveData.meta.shared_cities)) {
      return E.liveData.meta.shared_cities.indexOf(muniId) !== -1 || E.liveData.meta.shared_cities.indexOf(studyParent) !== -1;
    }
    return Boolean(DEMO_SHARED_CITIES[studyParent]);
  }

  function canEditCityDemo(muniId) {
    if (E.mode === 'live' && E.liveData && E.liveData.meta) {
      if (E.liveData.meta.role === 'super_admin') { return true; }
      return (E.liveData.meta.editable_cities || []).indexOf(muniId) !== -1;
    }
    var r = role();
    if (r.all) { return true; }
    var studyParent = (MUNI[muniId] && !MUNI[muniId].is_study_city && MUNI[muniId].near_city_id)
      ? MUNI[muniId].near_city_id
      : muniId;
    if (r.cities.indexOf(studyParent) === -1) { return false; }
    return !isSharedCity(studyParent);
  }

  function canCity(muniId) {
    var r = role();
    return r.all || r.cities.some(function (c) { return areaOf(c).indexOf(muniId) !== -1; });
  }

  function canEditService(s) {
    if (E.mode === 'live' && typeof s.editable === 'boolean') { return s.editable; }
    var r = role();
    if (r.all) { return true; }
    if (s.for_institution_id && r.inst.indexOf(s.for_institution_id) !== -1) { return true; }
    if (!s.for_institution_id && canEditCityDemo(s.municipality_id)) { return true; }
    return false;
  }

  function canEditLocal(l) {
    if (E.mode === 'live' && typeof l.editable === 'boolean') { return l.editable; }
    var r = role();
    if (r.all) { return true; }
    if (l.for_institution_id && r.inst.indexOf(l.for_institution_id) !== -1) { return true; }
    if (!l.for_institution_id && canEditCityDemo(l.municipality_id)) { return true; }
    return false;
  }

  function factMap() {
    if (E.mode === 'live' && E.liveData && Array.isArray(E.liveData.facts)) {
      var map = Object.create(null);
      E.liveData.facts.forEach(function (f) {
        map[f.fact_key] = Object.assign({ source: f.source_id }, f);
      });
      return map;
    }
    return C.facts || {};
  }
  function factKeys() { return Object.keys(factMap()).sort(); }
  function fact(k) { return Object.assign({}, factMap()[k], E.facts[k]); }
  function svcs() {
    if (E.mode === 'live' && E.liveData && Array.isArray(E.liveData.services)) {
      return E.liveData.services.map(function (s) {
        var sid = String(s.service_id);
        var acc = !(s.accepting_students === false || s.accepting_students === 'no' || s.accepting_students === 'false');
        var norm = {
          id: sid,
          service_id: sid,
          name: s.name,
          type: s.service_type,
          city_id: s.city_id,
          municipality_id: s.municipality_id || s.city_id,
          for_institution_id: s.for_institution_id || null,
          description: s.description,
          url: s.url,
          accepting_students: acc,
          related_step_id: s.related_step_id || null,
          source_id: s.source_id || null,
          last_verified: s.last_verified,
          editable: s.editable
        };
        return Object.assign(norm, E.services[sid]);
      }).concat(E.added);
    }
    return (C.services || []).map(function (s) {
      return Object.assign({}, s, E.services[String(s.id)]);
    }).concat(E.added);
  }
  function lkey(r) { return r.step_id + '|' + r.municipality_id + '|' + (r.for_institution_id || ''); }
  function locals() {
    if (E.mode === 'live' && E.liveData && Array.isArray(E.liveData.step_local)) {
      return E.liveData.step_local.map(function (r) {
        var base = Object.assign({ for_institution_id: '' }, r, { for_institution_id: r.for_institution_id || '' });
        return Object.assign(base, E.local[lkey(base)]);
      }).concat(E.addedLocal);
    }
    return (C.step_local || []).map(function (r) {
      var base = Object.assign({ for_institution_id: '' }, r);
      return Object.assign(base, E.local[lkey(base)]);
    }).concat(E.addedLocal);
  }
  function step(id) { return Object.assign({}, STEP[id], E.steps[id]); }
  function verified(kind, id, base) { return E.checked[kind + ':' + id] || base; }

  function age(d) {
    if (!d) { return STALE + 1; }
    return Math.round((new Date(TODAY) - new Date(d)) / DAY);
  }
  function due(d) {
    return new Date(new Date(d).getTime() + STALE * DAY).toISOString().slice(0, 10);
  }
  function nice(d) {
    try {
      return new Date(d + 'T12:00').toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
    } catch (_) {
      return d || '';
    }
  }

  function makeStamp(d) {
    var left = STALE - age(d);
    var wrap = make('div', 'meta');
    if (left < 0) {
      wrap.appendChild(make('span', 'tag due', 'Check now'));
      wrap.appendChild(document.createTextNode('Last checked ' + nice(d) + ', ' + (-left) + ' days overdue'));
    } else if (left <= 30) {
      wrap.appendChild(make('span', 'tag soon', 'Due soon'));
      wrap.appendChild(document.createTextNode('Check by ' + nice(due(d))));
    } else {
      wrap.appendChild(make('span', 'tag ok', 'Checked'));
      wrap.appendChild(document.createTextNode(nice(d) + ' · next check by ' + nice(due(d))));
    }
    return wrap;
  }

  function log(kind, ref, label, from, to, file, reason, op) {
    var r = role();
    E.pending.push({
      at: new Date().toISOString(),
      who: r.name,
      role: r.all ? 'super_admin' : 'editor',
      kind: kind,
      ref: ref,
      label: label,
      from: from,
      to: to,
      file: file,
      reason: reason || 'Updated via Staff Editor Panel',
      op: op || null
    });
  }

  function checkList() {
    var out = [];
    var r = role();
    svcs().forEach(function (s) {
      if (s.municipality_id && canCity(s.municipality_id)) {
        out.push({
          kind: 'service',
          id: s.id,
          d: verified('service', s.id, s.last_verified),
          t: s.name,
          m: ((MUNI[s.municipality_id] || {}).name || s.municipality_id) + ' · service' + (s.for_institution_id ? ' (' + s.for_institution_id + ')' : ''),
          city: fileOf(s.municipality_id).slice(5),
          editable: canEditService(s)
        });
      }
    });
    locals().forEach(function (l) {
      if (canCity(l.municipality_id)) {
        out.push({
          kind: 'local',
          id: lkey(l),
          d: verified('local', lkey(l), l.last_verified),
          t: (STEP[l.step_id] || {}).title || l.step_id,
          m: ((MUNI[l.municipality_id] || {}).name || l.municipality_id) + ' · local text' + (l.for_institution_id ? ' (' + l.for_institution_id + ')' : ''),
          city: fileOf(l.municipality_id).slice(5),
          editable: canEditLocal(l)
        });
      }
    });
    if (r.all) {
      factKeys().forEach(function (k) {
        var f = fact(k);
        out.push({ kind: 'fact', id: k, d: verified('fact', k, f.last_verified), t: f.label, m: 'Figure', editable: true });
      });
      if (E.mode !== 'live') {
        (C.steps || []).forEach(function (s) {
          out.push({ kind: 'step', id: s.id, d: verified('step', s.id, s.last_verified), t: step(s.id).title, m: 'Step', editable: true });
        });
      }
    }
    return out.sort(function (a, b) {
      return a.d < b.d ? -1 : (a.d > b.d ? 1 : String(a.t).localeCompare(String(b.t)));
    });
  }

  var TABS = [
    ['check', 'To check'],
    ['local', 'Local texts'],
    ['services', 'Services'],
    ['figures', 'Figures'],
    ['steps', 'Steps'],
    ['changes', 'Changes']
  ];

  function renderTabs() {
    var tabsHost = document.getElementById('tabs');
    if (!tabsHost) { return; }
    clearChildren(tabsHost);
    var dueSoonCount = checkList().filter(function (x) { return STALE - age(x.d) <= 30; }).length;
    var changeCount = E.mode === 'live' && E.liveData
      ? (E.pending.length || (E.liveData.changes || []).length)
      : E.pending.length;

    TABS.forEach(function (pair) {
      var k = pair[0];
      var label = pair[1];
      var btn = make('button', null, label);
      btn.type = 'button';
      btn.setAttribute('role', 'tab');
      btn.setAttribute('data-tab', k);
      btn.setAttribute('aria-selected', String(E.tab === k));
      if (k === 'changes' && changeCount) {
        btn.appendChild(make('span', 'count', changeCount));
      } else if (k === 'check' && dueSoonCount) {
        btn.appendChild(make('span', 'count', dueSoonCount));
      }
      tabsHost.appendChild(btn);
    });
  }

  function makeCitySelect() {
    var lbl = make('label', null, 'City');
    lbl.setAttribute('for', 'city');
    var sel = document.createElement('select');
    sel.id = 'city';
    role().cities.forEach(function (c) {
      var name = (MUNI[c] && MUNI[c].name) || c;
      if (isSharedCity(c) && !role().all) { name += ' (shared city)'; }
      var opt = make('option', null, name);
      opt.value = c;
      sel.appendChild(opt);
    });
    sel.value = E.city;
    lbl.appendChild(sel);
    return lbl;
  }

  function addFormField(form, labelText, inputEl) {
    var lbl = make('label', null, labelText);
    lbl.appendChild(inputEl);
    form.appendChild(lbl);
  }

  function makeInput(name, id, val, type, extra) {
    var el = document.createElement('input');
    el.name = name;
    el.id = id;
    el.type = type || 'text';
    el.value = val === null || val === undefined ? '' : String(val);
    if (extra) { Object.keys(extra).forEach(function (k) { el[k] = extra[k]; }); }
    return el;
  }

  function makeTextarea(name, id, val) {
    var el = document.createElement('textarea');
    el.name = name;
    el.id = id;
    el.value = val || '';
    return el;
  }

  function renderPubBar() {
    var pub = document.getElementById('pub');
    var pubText = document.getElementById('pubText');
    if (!pub || !pubText) { return; }
    pub.hidden = !E.pending.length;
    if (!E.pending.length) { return; }
    clearChildren(pubText);
    pubText.appendChild(make('strong', null, E.pending.length + ' change' + (E.pending.length === 1 ? '' : 's') + ' ready. '));
    pubText.appendChild(document.createTextNode('Files: '));
    var seen = Object.create(null);
    var files = [];
    E.pending.forEach(function (c) {
      if (!Object.prototype.hasOwnProperty.call(seen, c.file)) {
        seen[c.file] = true;
        files.push(c.file);
      }
    });
    files.sort().forEach(function (f, idx) {
      if (idx > 0) { pubText.appendChild(document.createTextNode(' ')); }
      pubText.appendChild(make('code', null, f + '.json'));
    });
  }

  function updateBannerAndRoleSelect() {
    var roleSel = document.getElementById('nl-role-sim');
    if (roleSel) {
      roleSel.disabled = (E.mode === 'live');
    }
    var banner = document.getElementById('nl-editor-banner');
    if (!banner) { return; }
    clearChildren(banner);
    if (E.mode === 'live' && E.liveData) {
      var meta = E.liveData.meta || {};
      banner.appendChild(make('strong', null, 'Connected to Live /api/editor · '));
      banner.appendChild(document.createTextNode(
        'Role: ' + (meta.role || 'editor') +
        (meta.institution_id ? ' (' + meta.institution_id + ')' : '') +
        ' · Editable single-school cities: ' + ((meta.editable_cities || []).join(', ') || 'none (overrides only)') +
        (typeof meta.stale_count === 'number' ? ' · Stale in scope: ' + meta.stale_count : '')
      ));
    } else {
      banner.appendChild(make('strong', null, DEFAULT_BANNER_PREFIX));
      banner.appendChild(document.createTextNode(DEFAULT_BANNER_BODY));
    }
  }

  function renderView() {
    var root = document.getElementById('view');
    if (!root) { return; }
    clearChildren(root);

    var r = role();
    if (r.cities.indexOf(E.city) === -1) { E.city = r.cities[0] || 'the-hague'; }

    updateBannerAndRoleSelect();

    if (E.formErr && !E.open) {
      var errBanner = make('div', 'err-msg', E.formErr);
      errBanner.setAttribute('role', 'alert');
      errBanner.style.marginBottom = '12px';
      root.appendChild(errBanner);
    }

    if (E.tab === 'check') {
      var list = checkList();
      var overdue = list.filter(function (x) { return STALE - age(x.d) < 0; }).length;
      var head = make('div');
      head.appendChild(make('h2', null, 'To check'));
      head.appendChild(make('p', 'sub',
        'Everything in your scope, oldest verification first (target: every ' + STALE + ' days). ' +
        (overdue ? overdue + ' items are overdue.' : 'Nothing is overdue today.')));
      root.appendChild(head);

      var card = make('div', 'card');
      if (!list.length) {
        card.appendChild(make('div', 'empty', 'Nothing to check.'));
      } else {
        var visible = E.showAllCheck ? list : list.slice(0, 60);
        visible.forEach(function (x) {
          var item = make('div', 'item');
          var top = make('div', 'top');
          var t = make('div', 't');
          t.appendChild(make('strong', null, x.t));
          t.appendChild(make('span', 'meta', x.m));
          top.appendChild(t);
          if (x.editable) {
            var chkBtn = make('button', 'btn', 'Mark as checked');
            chkBtn.type = 'button';
            chkBtn.setAttribute('data-checked', x.kind + ':' + x.id);
            chkBtn.setAttribute('data-label', x.t);
            chkBtn.setAttribute('data-file', (x.kind === 'service' || x.kind === 'local') ? 'city-' + x.city : 'core');
            top.appendChild(chkBtn);
          } else {
            top.appendChild(make('span', 'tag locktag', 'Shared city lock'));
          }
          item.appendChild(top);
          item.appendChild(makeStamp(x.d));
          card.appendChild(item);
        });
        if (list.length > 60) {
          var moreItem = make('div', 'item');
          var moreTop = make('div', 'top');
          moreTop.appendChild(make('span', 'meta', 'Showing ' + visible.length + ' of ' + list.length + ' items.'));
          var togBtn = make('button', 'btn', E.showAllCheck ? 'Show first 60' : 'Show all ' + list.length + ' items');
          togBtn.type = 'button';
          togBtn.setAttribute('data-toggle-all-check', '1');
          moreTop.appendChild(togBtn);
          moreItem.appendChild(moreTop);
          card.appendChild(moreItem);
        }
      }
      root.appendChild(card);
    }

    if (E.tab === 'local') {
      var a = areaOf(E.city);
      var llist = locals().filter(function (l) { return a.indexOf(l.municipality_id) !== -1; }).sort(function (x, y) {
        return ((STEP[x.step_id] || {}).sort_order || 0) - ((STEP[y.step_id] || {}).sort_order || 0) ||
          x.municipality_id.localeCompare(y.municipality_id);
      });
      var lTag = instLabel();
      var lHead = make('div');
      lHead.appendChild(make('h2', null, 'Local texts'));
      lHead.appendChild(make('p', 'sub', 'City-specific guidance shown on steps. Shared cities lock municipal rows for institutional editors; use "Create ' + lTag + ' override" to tailor guidance for your own students.'));
      root.appendChild(lHead);

      var tools = make('div', 'tools');
      tools.appendChild(makeCitySelect());
      root.appendChild(tools);

      var lCard = make('div', 'card');
      if (!llist.length) {
        lCard.appendChild(make('div', 'empty', 'No local texts for this city yet.'));
      } else {
        llist.forEach(function (l) {
          var k = lkey(l);
          var isOpen = E.open === 'local:' + k;
          var isOverrideOpen = E.open === 'override-local:' + k;
          var editable = canEditLocal(l);

          var item = make('div', 'item');
          var top = make('div', 'top');
          var t = make('div', 't');
          t.appendChild(make('strong', null, (STEP[l.step_id] && STEP[l.step_id].title) || l.step_id));
          var meta = make('span', 'meta', ((MUNI[l.municipality_id] && MUNI[l.municipality_id].name) || l.municipality_id));
          if (l.for_institution_id) {
            meta.appendChild(document.createTextNode(' · '));
            meta.appendChild(make('span', 'tag new', 'override: ' + l.for_institution_id));
          } else if (isSharedCity(l.municipality_id)) {
            meta.appendChild(document.createTextNode(' · '));
            meta.appendChild(make('span', 'tag locktag', 'shared municipal'));
          }
          if (E.local[k]) {
            meta.appendChild(document.createTextNode(' '));
            meta.appendChild(make('span', 'tag new', 'Edited'));
          }
          t.appendChild(meta);
          top.appendChild(t);

          if (!isOpen && !isOverrideOpen) {
            if (editable) {
              var edBtn = make('button', 'btn', 'Edit');
              edBtn.type = 'button';
              edBtn.setAttribute('data-open', 'local:' + k);
              top.appendChild(edBtn);
            } else {
              var ovBtn = make('button', 'btn', 'Create ' + lTag + ' override');
              ovBtn.type = 'button';
              ovBtn.setAttribute('data-open', 'override-local:' + k);
              top.appendChild(ovBtn);
            }
          }
          item.appendChild(top);

          if (isOpen || isOverrideOpen) {
            var form = make('form', 'nl-inline');
            form.setAttribute('data-save', isOverrideOpen ? 'local-override' : 'local');
            form.setAttribute('data-id', k);
            addFormField(form, isOverrideOpen ? (lTag + ' override text shown to students') : 'Text shown to students', makeTextarea('body', 'f_body', l.body));
            addFormField(form, 'Change reason (min 3 characters, stored in staff_change)', makeInput('reason', 'f_reason', '', 'text', { placeholder: 'e.g. Updated arrival days instructions', required: true, minLength: 3 }));
            if (E.formErr) { form.appendChild(make('div', 'err-msg', E.formErr)); }
            var acts = make('div', 'acts');
            var saveBtn = make('button', 'btn fill', isOverrideOpen ? ('Save ' + lTag + ' override') : 'Save');
            saveBtn.type = 'submit';
            var cancelBtn = make('button', 'btn', 'Cancel');
            cancelBtn.type = 'button';
            cancelBtn.setAttribute('data-open', '');
            acts.appendChild(saveBtn);
            acts.appendChild(cancelBtn);
            form.appendChild(acts);
            item.appendChild(form);
          } else {
            item.appendChild(make('div', 'body', l.body));
          }
          lCard.appendChild(item);
        });
      }
      root.appendChild(lCard);
    }

    if (E.tab === 'services') {
      var sa = areaOf(E.city);
      var types = ['gp', 'housing', 'support', 'community', 'government', 'banking', 'legal', 'municipal', 'other'];
      var slist = svcs().filter(function (s) {
        return sa.indexOf(s.municipality_id) !== -1 && (!E.svcType || s.type === E.svcType);
      });
      var sTag = instLabel();

      var sHead = make('div');
      sHead.appendChild(make('h2', null, 'Services'));
      sHead.appendChild(make('p', 'sub', 'GPs, housing, help desks, government counters and communities shown under Local help. In shared cities, ' + sTag + ' can add or edit ' + sTag + '-scoped services while shared municipal entries stay protected by can_edit_city().'));
      root.appendChild(sHead);

      var sTools = make('div', 'tools');
      sTools.appendChild(makeCitySelect());
      var typeLbl = make('label', null, 'Type');
      typeLbl.setAttribute('for', 'stype');
      var typeSel = document.createElement('select');
      typeSel.id = 'stype';
      var allOpt = make('option', null, 'All types');
      allOpt.value = '';
      typeSel.appendChild(allOpt);
      types.forEach(function (t) {
        var o = make('option', null, t);
        o.value = t;
        typeSel.appendChild(o);
      });
      typeSel.value = E.svcType;
      typeLbl.appendChild(typeSel);
      sTools.appendChild(typeLbl);

      var addBtn = make('button', 'btn', 'Add a service');
      addBtn.type = 'button';
      addBtn.setAttribute('data-open', 'service:new');
      sTools.appendChild(addBtn);
      root.appendChild(sTools);

      var makeSvcForm = function (s, modeFlag) {
        var form = make('form', 'nl-inline');
        form.setAttribute('data-save', modeFlag === 'new' ? 'service-new' : (modeFlag === 'copy' ? 'service-copy' : 'service'));
        form.setAttribute('data-id', s.id ? String(s.id) : 'new');

        var rowf = make('div', 'rowf');
        var nameInp = makeInput('name', 'f_name', s.name || '', 'text', { required: true, maxLength: 80 });
        var typSel = document.createElement('select');
        typSel.name = 'type';
        typSel.id = 'f_type';
        typSel.style.width = '100%';
        types.forEach(function (t) {
          var o = make('option', null, t);
          o.value = t;
          typSel.appendChild(o);
        });
        typSel.value = (s.type && types.indexOf(s.type) !== -1) ? s.type : 'gp';
        addFormField(rowf, 'Name', nameInp);
        addFormField(rowf, 'Type', typSel);
        form.appendChild(rowf);

        addFormField(form, 'Description', makeTextarea('description', 'f_desc', s.description || ''));
        addFormField(form, 'Website (https://)', makeInput('url', 'f_url', s.url || '', 'url', { placeholder: 'https://...', required: true }));

        var chkLbl = make('label', 'chk');
        var chk = makeInput('accepting', 'f_acc', '', 'checkbox');
        chk.checked = s.accepting_students !== false;
        chkLbl.appendChild(chk);
        chkLbl.appendChild(document.createTextNode('Taking new students now'));
        form.appendChild(chkLbl);

        addFormField(form, 'Change reason (min 3 characters)', makeInput('reason', 'f_reason', '', 'text', { placeholder: 'e.g. Confirmed 2026 intake acceptance & HTTPS URL', required: true, minLength: 3 }));
        if (E.formErr) { form.appendChild(make('div', 'err-msg', E.formErr)); }

        var acts = make('div', 'acts');
        var sub = make('button', 'btn fill', modeFlag === 'new' ? 'Add service' : (modeFlag === 'copy' ? ('Save ' + sTag + ' copy') : 'Save'));
        sub.type = 'submit';
        var can = make('button', 'btn', 'Cancel');
        can.type = 'button';
        can.setAttribute('data-open', '');
        acts.appendChild(sub);
        acts.appendChild(can);
        form.appendChild(acts);
        return form;
      };

      var sCard = make('div', 'card');
      if (E.open === 'service:new') {
        var newWrap = make('div', 'item');
        newWrap.appendChild(makeSvcForm({ type: E.svcType || 'support' }, 'new'));
        sCard.appendChild(newWrap);
      }

      if (!slist.length && E.open !== 'service:new') {
        sCard.appendChild(make('div', 'empty', 'No services of this type here yet.'));
      } else {
        slist.forEach(function (s) {
          var sid = String(s.id);
          var isOpen = E.open === 'service:' + sid;
          var isCopy = E.open === 'service-copy:' + sid;
          var editable = canEditService(s);

          var item = make('div', 'item');
          var top = make('div', 'top');
          var t = make('div', 't');
          t.appendChild(make('strong', null, s.name));
          var meta = make('span', 'meta', s.type + ' · ' + ((MUNI[s.municipality_id] && MUNI[s.municipality_id].name) || s.municipality_id) + ' · ' + (s.accepting_students === false ? 'Not taking new students' : 'Taking new students'));
          if (s.for_institution_id) {
            meta.appendChild(document.createTextNode(' · '));
            meta.appendChild(make('span', 'tag ok', 'inst: ' + s.for_institution_id));
          } else if (isSharedCity(s.municipality_id)) {
            meta.appendChild(document.createTextNode(' · '));
            meta.appendChild(make('span', 'tag locktag', 'shared municipal'));
          }
          if (E.services[sid] || sid.indexOf('n') === 0) {
            meta.appendChild(document.createTextNode(' '));
            meta.appendChild(make('span', 'tag new', 'Edited'));
          }
          t.appendChild(meta);
          top.appendChild(t);

          if (!isOpen && !isCopy) {
            if (editable) {
              var edBtn = make('button', 'btn', 'Edit');
              edBtn.type = 'button';
              edBtn.setAttribute('data-open', 'service:' + sid);
              top.appendChild(edBtn);
            } else {
              var cpBtn = make('button', 'btn', 'Create ' + sTag + ' copy');
              cpBtn.type = 'button';
              cpBtn.setAttribute('data-open', 'service-copy:' + sid);
              top.appendChild(cpBtn);
            }
          }
          item.appendChild(top);

          if (isOpen) {
            item.appendChild(makeSvcForm(s, 'edit'));
          } else if (isCopy) {
            item.appendChild(makeSvcForm(Object.assign({}, s, { name: s.name + ' (' + sTag + ' note)' }), 'copy'));
          } else {
            item.appendChild(make('div', 'body', s.description));
            if (s.url) { item.appendChild(make('div', 'meta', s.url)); }
          }
          sCard.appendChild(item);
        });
      }
      root.appendChild(sCard);
    }

    if (E.tab === 'figures') {
      var fHead = make('div');
      fHead.appendChild(make('h2', null, 'Figures'));
      fHead.appendChild(make('p', 'sub', 'National figures and deadlines (e.g. CAK fine). Publishing starts a new dated row and automatically sets valid_to on the previous active version.'));
      root.appendChild(fHead);

      var fCard = make('div', 'card');
      factKeys().forEach(function (k) {
        var f = fact(k);
        var isOpen = E.open === 'fact:' + k;
        var item = make('div', 'item');
        var top = make('div', 'top');
        var t = make('div', 't');
        t.appendChild(make('strong', null, f.label + ': ' + f.value + (f.unit ? ' ' + f.unit : '')));
        var meta = make('span', 'meta', ((STEP[f.step_id] || {}).title || '') + ' · valid from ' + nice(f.valid_from || f.last_verified));
        if (E.facts[k]) {
          meta.appendChild(document.createTextNode(' '));
          meta.appendChild(make('span', 'tag new', 'New version'));
        }
        t.appendChild(meta);
        top.appendChild(t);
        if (r.all && !isOpen) {
          var nvBtn = make('button', 'btn', 'New value');
          nvBtn.type = 'button';
          nvBtn.setAttribute('data-open', 'fact:' + k);
          top.appendChild(nvBtn);
        }
        item.appendChild(top);

        if (isOpen && r.all) {
          var form = make('form', 'nl-inline');
          form.setAttribute('data-save', 'fact');
          form.setAttribute('data-id', k);
          var rowf = make('div', 'rowf');
          addFormField(rowf, 'New value' + (f.unit ? ' (' + f.unit + ')' : ''), makeInput('value', 'f_value', '', 'text', { required: true }));
          addFormField(rowf, 'Valid from', makeInput('from', 'f_from', TODAY, 'date', { required: true }));
          form.appendChild(rowf);
          addFormField(form, 'Change reason (min 3 characters)', makeInput('reason', 'f_reason', '', 'text', { placeholder: 'e.g. Annual CAK 2027 rate adjustment', required: true, minLength: 3 }));
          form.appendChild(make('p', 'meta', 'Previous value (' + f.value + ') stays preserved in version history.'));
          if (E.formErr) { form.appendChild(make('div', 'err-msg', E.formErr)); }
          var acts = make('div', 'acts');
          var sub = make('button', 'btn fill', 'Publish new version');
          sub.type = 'submit';
          var can = make('button', 'btn', 'Cancel');
          can.type = 'button';
          can.setAttribute('data-open', '');
          acts.appendChild(sub);
          acts.appendChild(can);
          form.appendChild(acts);
          item.appendChild(form);
        }
        fCard.appendChild(item);
      });
      root.appendChild(fCard);
      if (!r.all) {
        root.appendChild(make('p', 'lock', 'Only the national project team (super_admin) changes Figures. Switch role in the top right to test publishing a new version.'));
      }
    }

    if (E.tab === 'steps') {
      var stHead = make('div');
      stHead.appendChild(make('h2', null, 'Steps'));
      stHead.appendChild(make('p', 'sub', 'National student journey steps. Local city differences belong under Local texts.'));
      root.appendChild(stHead);

      var stCard = make('div', 'card');
      (C.steps || []).forEach(function (s0) {
        var s = step(s0.id);
        var isOpen = E.open === 'step:' + s.id;
        var item = make('div', 'item');
        var top = make('div', 'top');
        var t = make('div', 't');
        t.appendChild(make('strong', null, s.title));
        var meta = make('span', 'meta', String(s.phase || '').replace('_', ' ') + (s.is_optional ? ' · optional' : ''));
        if (E.steps[s.id]) {
          meta.appendChild(document.createTextNode(' '));
          meta.appendChild(make('span', 'tag new', 'Edited'));
        }
        t.appendChild(meta);
        top.appendChild(t);
        if (r.all && !isOpen) {
          var edBtn = make('button', 'btn', 'Edit');
          edBtn.type = 'button';
          edBtn.setAttribute('data-open', 'step:' + s.id);
          top.appendChild(edBtn);
        }
        item.appendChild(top);

        if (isOpen && r.all) {
          var form = make('form', 'nl-inline');
          form.setAttribute('data-save', 'step');
          form.setAttribute('data-id', s.id);
          addFormField(form, 'Title', makeInput('title', 'f_title', s.title, 'text', { required: true, maxLength: 90 }));
          addFormField(form, 'One-line summary', makeInput('summary', 'f_summary', s.summary, 'text', { required: true, maxLength: 160 }));
          addFormField(form, 'How to do it', makeTextarea('how_to', 'f_how', s.how_to));
          addFormField(form, 'Change reason', makeInput('reason', 'f_reason', '', 'text', { required: true, minLength: 3 }));
          if (E.formErr) { form.appendChild(make('div', 'err-msg', E.formErr)); }
          var acts = make('div', 'acts');
          var sub = make('button', 'btn fill', E.mode === 'live' ? 'Save local draft (Export JSON)' : 'Save');
          sub.type = 'submit';
          var can = make('button', 'btn', 'Cancel');
          can.type = 'button';
          can.setAttribute('data-open', '');
          acts.appendChild(sub);
          acts.appendChild(can);
          form.appendChild(acts);
          item.appendChild(form);
        } else {
          item.appendChild(make('div', 'body', s.summary));
        }
        stCard.appendChild(item);
      });
      root.appendChild(stCard);
      if (E.mode === 'live') {
        root.appendChild(make('p', 'lock', 'National Steps are stored in the repository build rather than /api/editor. Edits saved here queue as local drafts for Export JSON.'));
      } else if (!r.all) {
        root.appendChild(make('p', 'lock', 'Only the project team edits national steps. Switch role in the top right to edit.'));
      }
    }

    if (E.tab === 'changes') {
      var chHead = make('div');
      chHead.appendChild(make('h2', null, 'Changes (staff_change audit log)'));
      chHead.appendChild(make('p', 'sub', 'Saved edits queue here until Publish. Every change records actor, reason, and before/after diff.'));
      root.appendChild(chHead);

      var renderChangeCard = function (items, emptyMsg) {
        var cCard = make('div', 'card');
        if (!items.length) {
          cCard.appendChild(make('div', 'empty', emptyMsg));
          return cCard;
        }
        items.forEach(function (c) {
          var item = make('div', 'item');
          var top = make('div', 'top');
          var t = make('div', 't');
          t.appendChild(make('strong', null, c.label || (c.entity_type + ': ' + c.entity_key)));
          var ts = c.at || c.changed_at;
          var dt = ts ? new Date(ts).toLocaleString('en-GB', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) : '';
          var meta = make('span', 'meta', (c.kind || c.action) + ' · ' + (c.who || c.actor_sub) + ' · ' + dt);
          if (c.file) {
            meta.appendChild(document.createTextNode(' · file '));
            meta.appendChild(make('code', null, c.file + '.json'));
          }
          t.appendChild(meta);
          if (c.reason) { t.appendChild(make('div', 'meta', 'Reason: ' + c.reason)); }
          top.appendChild(t);
          item.appendChild(top);
          if (c.from !== null && c.from !== undefined || c.to !== null && c.to !== undefined) {
            var diff = make('div', 'body diff');
            if (c.from !== null && c.from !== undefined) {
              diff.appendChild(make('del', null, String(c.from).slice(0, 220)));
              diff.appendChild(document.createTextNode(' '));
            }
            if (c.to !== null && c.to !== undefined) {
              diff.appendChild(make('ins', null, String(c.to).slice(0, 220)));
            }
            item.appendChild(diff);
          }
          cCard.appendChild(item);
        });
        return cCard;
      };

      root.appendChild(renderChangeCard(E.pending.slice().reverse(), 'No pending changes waiting.'));

      if (E.mode === 'live' && E.liveData && Array.isArray(E.liveData.changes) && E.liveData.changes.length) {
        var lh = make('div');
        lh.appendChild(make('h2', null, 'Server staff_change log'));
        root.appendChild(lh);
        root.appendChild(renderChangeCard(E.liveData.changes, 'No server log entries.'));
      } else if (E.published.length) {
        var ph = make('div');
        ph.appendChild(make('h2', null, 'Published from this browser'));
        root.appendChild(ph);
        root.appendChild(renderChangeCard(E.published.slice().reverse().slice(0, 30), ''));
      }
    }

    renderTabs();
    renderPubBar();
    keep();
  }

  function callLiveEditor(subpath, method, body) {
    if (subpath !== '' && !Object.prototype.hasOwnProperty.call(ALLOWED_SUBPATHS, subpath)) {
      return Promise.reject(new Error('Invalid editor endpoint'));
    }
    var root = document.getElementById('view');
    var base = (root && root.getAttribute('data-endpoint')) || FALLBACK_ENDPOINT;
    var token = null;
    try { token = sessionStorage.getItem(STAFF_TOKEN_KEY); } catch (_) {}
    if (!token) { return Promise.reject(new Error('Missing staff JWT')); }

    var controller = (typeof AbortController === 'function') ? new AbortController() : null;
    var timer = setTimeout(function () { if (controller) { controller.abort(); } }, TIMEOUT_MS);
    var opts = {
      method: method,
      credentials: 'omit',
      referrerPolicy: 'no-referrer',
      cache: 'no-store',
      headers: { Authorization: 'Bearer ' + token },
      signal: controller ? controller.signal : undefined
    };
    if (method === 'POST') {
      opts.headers['Content-Type'] = 'application/json';
      opts.body = JSON.stringify(body);
    }

    return fetch(base + subpath, opts).then(function (resp) {
      clearTimeout(timer);
      return resp.json().catch(function () { return {}; }).then(function (json) {
        if (!resp.ok) { throw new Error(json.detail || json.error || ('HTTP ' + resp.status)); }
        return json;
      });
    }, function (err) {
      clearTimeout(timer);
      throw err;
    });
  }

  function clearDemoEdits() {
    E.pending = [];
    E.facts = Object.create(null);
    E.services = Object.create(null);
    E.added = [];
    E.local = Object.create(null);
    E.addedLocal = [];
    E.steps = Object.create(null);
    E.checked = Object.create(null);
    E.open = null;
  }

  function loadLiveEditor(isManual) {
    callLiveEditor('', 'GET', null).then(function (data) {
      var prevInst = E.liveData && E.liveData.meta ? E.liveData.meta.institution_id : null;
      var nextInst = data && data.meta ? data.meta.institution_id : null;
      if (E.mode !== 'live' || prevInst !== nextInst) {
        clearDemoEdits();
      }
      E.mode = 'live';
      E.liveData = data;
      E.formErr = '';
      renderView();
    }).catch(function (err) {
      E.mode = 'demo';
      E.liveData = null;
      if (isManual) {
        E.formErr = 'Could not connect to live /api/editor: ' + (err && err.message ? err.message : 'request failed');
      }
      renderView();
    });
  }

  function exportJsonPatch() {
    var r = role();
    var out = {
      exported_at: new Date().toISOString(),
      role: r.all ? 'super_admin' : (r.inst[0] || E.login),
      pending: E.pending,
      published: E.published,
      edits: {
        facts: E.facts,
        services: E.services,
        added_services: E.added,
        local_texts: E.local,
        added_local: E.addedLocal,
        steps: E.steps,
        checked: E.checked
      }
    };
    var blob = new Blob([JSON.stringify(out, null, 2)], { type: 'application/json;charset=utf-8' });
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url;
    a.download = 'netherlanded-editor-patch.json';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
  }

  function handlePublish() {
    if (E.publishing) { return; }
    if (E.mode === 'live') {
      var liveOps = E.pending.filter(function (p) { return Boolean(p.op); });
      var draftOnly = E.pending.filter(function (p) { return !p.op; });
      if (!liveOps.length) {
        E.formErr = 'Pending changes are local-only drafts (e.g. Steps); use Export JSON to save them.';
        renderView();
        return;
      }
      E.publishing = true;
      E.formErr = '';
      var pubBtnEl = document.getElementById('publish');
      if (pubBtnEl) { pubBtnEl.disabled = true; }
      var doneCount = 0;

      var runNext = function (idx) {
        if (idx >= liveOps.length) {
          E.publishing = false;
          if (pubBtnEl) { pubBtnEl.disabled = false; }
          E.facts = Object.create(null);
          E.services = Object.create(null);
          E.added = [];
          E.local = Object.create(null);
          E.addedLocal = [];
          E.checked = Object.create(null);
          E.pending = draftOnly;
          E.tab = 'changes';
          if (draftOnly.length) {
            E.formErr = 'Published ' + doneCount + ' change(s). ' + draftOnly.length + ' local-only draft(s) remain in pending for Export JSON.';
          }
          loadLiveEditor(false);
          return;
        }
        var item = liveOps[idx];
        callLiveEditor(item.op.subpath, 'POST', item.op.body).then(function () {
          doneCount += 1;
          E.published.push(item);
          var pos = E.pending.indexOf(item);
          if (pos !== -1) { E.pending.splice(pos, 1); }
          runNext(idx + 1);
        }).catch(function (err) {
          E.publishing = false;
          if (pubBtnEl) { pubBtnEl.disabled = false; }
          E.formErr = 'Publish to /api/editor stopped (' + doneCount + '/' + liveOps.length + ' saved): ' + err.message;
          renderView();
        });
      };

      runNext(0);
      return;
    }
    E.published = E.published.concat(E.pending);
    E.pending = [];
    E.tab = 'changes';
    renderView();
  }

  function wireEvents() {
    var roleSel = document.getElementById('nl-role-sim');
    var authForm = document.getElementById('nl-editor-auth-form');
    var tokenInput = document.getElementById('nl-editor-token');
    var clearBtn = document.getElementById('nl-editor-clear');
    var demoBtn = document.getElementById('nl-editor-demo-btn');
    var exportBtn = document.getElementById('nl-export-patch');
    var discardBtn = document.getElementById('discard');
    var pubBtn = document.getElementById('publish');

    if (roleSel) {
      roleSel.value = E.login;
      roleSel.addEventListener('change', function () {
        E.login = ROLES[roleSel.value] ? roleSel.value : 'thuas';
        E.open = null;
        E.formErr = '';
        renderView();
      });
    }

    if (authForm && tokenInput) {
      authForm.addEventListener('submit', function (ev) {
        ev.preventDefault();
        var val = String(tokenInput.value || '').trim();
        if (!val) { return; }
        try { sessionStorage.setItem(STAFF_TOKEN_KEY, val); } catch (_) {}
        tokenInput.value = '';
        loadLiveEditor(true);
      });
    }

    if (clearBtn) {
      clearBtn.addEventListener('click', function () {
        try { sessionStorage.removeItem(STAFF_TOKEN_KEY); } catch (_) {}
        if (tokenInput) { tokenInput.value = ''; }
        E.mode = 'demo';
        E.liveData = null;
        E.formErr = '';
        renderView();
      });
    }

    if (demoBtn) {
      demoBtn.addEventListener('click', function () {
        E.mode = 'demo';
        E.formErr = '';
        renderView();
      });
    }

    if (exportBtn) { exportBtn.addEventListener('click', exportJsonPatch); }
    if (discardBtn) {
      discardBtn.addEventListener('click', function () {
        E.pending = [];
        E.facts = Object.create(null);
        E.services = Object.create(null);
        E.added = [];
        E.local = Object.create(null);
        E.addedLocal = [];
        E.steps = Object.create(null);
        E.checked = Object.create(null);
        E.open = null;
        E.formErr = '';
        renderView();
      });
    }
    if (pubBtn) { pubBtn.addEventListener('click', handlePublish); }

    document.addEventListener('click', function (ev) {
      var b = ev.target && ev.target.closest ? ev.target.closest('button') : null;
      if (!b) { return; }
      if (b.getAttribute('data-tab')) {
        E.tab = b.getAttribute('data-tab');
        E.open = null;
        E.formErr = '';
        renderView();
        window.scrollTo(0, 0);
        return;
      }
      if (b.hasAttribute('data-open')) {
        E.open = b.getAttribute('data-open') || null;
        E.formErr = '';
        renderView();
        return;
      }
      if (b.getAttribute('data-toggle-all-check')) {
        E.showAllCheck = !E.showAllCheck;
        renderView();
        return;
      }
      if (b.getAttribute('data-checked')) {
        var cid = b.getAttribute('data-checked');
        var kind = cid.split(':')[0];
        var entityType = kind === 'local' ? 'step_local' : kind;
        var verifyOp = (entityType === 'service' || entityType === 'step_local' || entityType === 'fact') ? {
          subpath: '/verify',
          body: { entity_type: entityType, entity_key: cid.split(':').slice(1).join(':'), reason: 'Verified against official source' }
        } : null;
        E.checked[cid] = TODAY;
        log('Checked', cid, b.getAttribute('data-label'), null, 'Checked against source on ' + nice(TODAY), b.getAttribute('data-file'), 'Verified against official source', verifyOp);
        renderView();
      }
    });

    document.addEventListener('change', function (ev) {
      var t = ev.target;
      if (!t) { return; }
      if (t.id === 'city') { E.city = t.value; E.open = null; E.formErr = ''; renderView(); }
      if (t.id === 'stype') { E.svcType = t.value; E.formErr = ''; renderView(); }
    });

    document.addEventListener('submit', function (ev) {
      var f = ev.target;
      if (!f || !f.getAttribute('data-save')) { return; }
      ev.preventDefault();
      var saveKind = f.getAttribute('data-save');
      var id = f.getAttribute('data-id');
      var valOf = function (n) { return (f.elements[n] && f.elements[n].value || '').trim(); };
      var reason = valOf('reason');
      if (reason.length < 3) {
        E.formErr = 'Change reason is required (minimum 3 characters).';
        renderView();
        return;
      }
      E.formErr = '';

      if (saveKind === 'local' || saveKind === 'local-override') {
        var curL = locals().find(function (l) { return lkey(l) === id; });
        var body = valOf('body');
        if (!body) { E.formErr = 'Guidance text cannot be empty.'; renderView(); return; }
        if (saveKind === 'local-override') {
          var instId = role().inst[0] || 'thuas';
          var ov = { step_id: curL.step_id, municipality_id: curL.municipality_id, for_institution_id: instId, body: body, links: curL.links || [], last_verified: TODAY };
          E.addedLocal.push(ov);
          log('Local override', lkey(ov), ((STEP[curL.step_id] || {}).title || curL.step_id) + ' (' + instId + ' in ' + curL.municipality_id + ')', curL.body, body, fileOf(curL.municipality_id), reason, {
            subpath: '/step-local',
            body: { payload: ov, reason: reason }
          });
        } else if (curL && body !== curL.body) {
          E.local[id] = { body: body, last_verified: TODAY };
          E.checked['local:' + id] = TODAY;
          log('Local text', id, ((STEP[curL.step_id] || {}).title || curL.step_id) + ' in ' + curL.municipality_id, curL.body, body, fileOf(curL.municipality_id), reason, {
            subpath: '/step-local',
            body: { payload: Object.assign({}, curL, { body: body }), reason: reason }
          });
        }
      } else if (saveKind === 'service-new' || saveKind === 'service-copy' || saveKind === 'service') {
        var url = valOf('url');
        if (!url || !/^https:\/\/[^\s"'<>\\]+$/.test(url)) {
          E.formErr = 'Valid website URL starting with https:// (no spaces or backslashes) is required.';
          renderView();
          return;
        }
        var nu = {
          name: valOf('name'),
          type: valOf('type'),
          description: valOf('description'),
          url: url,
          accepting_students: Boolean(f.elements.accepting && f.elements.accepting.checked),
          last_verified: TODAY
        };
        if (!nu.name || !nu.description) {
          E.formErr = 'Service name and description are required.';
          renderView();
          return;
        }
        var accStr = nu.accepting_students ? 'yes' : 'no';
        if (saveKind === 'service-new' || saveKind === 'service-copy') {
          var origS = saveKind === 'service-copy' ? svcs().find(function (s) { return String(s.id) === String(id); }) : null;
          var targetMuni = (origS && origS.municipality_id) ? origS.municipality_id : E.city;
          var instScope = role().all ? null : (role().inst[0] || 'thuas');
          var newSvc = Object.assign({
            id: 'n' + Date.now(),
            municipality_id: targetMuni,
            city: (MUNI[targetMuni] && MUNI[targetMuni].name) || targetMuni,
            for_institution_id: instScope,
            related_step_id: origS ? origS.related_step_id : null,
            source_id: origS ? origS.source_id : null
          }, nu);
          E.added.push(newSvc);
          log(saveKind === 'service-copy' ? 'Service copy' : 'Service added', String(newSvc.id), nu.name + ' in ' + newSvc.city, null, nu.description, fileOf(targetMuni), reason, {
            subpath: '/service',
            body: {
              payload: {
                service_id: String(newSvc.id),
                name: nu.name,
                service_type: nu.type,
                city_id: targetMuni,
                municipality_id: targetMuni,
                for_institution_id: instScope,
                description: nu.description,
                url: url,
                accepting_students: accStr
              },
              reason: reason
            }
          });
        } else {
          var curS = svcs().find(function (s) { return String(s.id) === String(id); });
          if (curS) {
            var ad = E.added.find(function (s) { return String(s.id) === String(id); });
            if (ad) { Object.assign(ad, nu); } else { E.services[String(curS.id)] = Object.assign({}, E.services[String(curS.id)], nu); }
            var targetSvcId = curS.service_id ? String(curS.service_id) : (/^[a-z0-9_-]{2,64}$/.test(String(curS.id)) ? String(curS.id) : ('svc_' + curS.id));
            log('Service', targetSvcId, nu.name, curS.description, nu.description, fileOf(curS.municipality_id), reason, {
              subpath: '/service',
              body: {
                payload: {
                  service_id: targetSvcId,
                  name: nu.name,
                  service_type: nu.type,
                  city_id: curS.municipality_id,
                  municipality_id: curS.municipality_id,
                  for_institution_id: curS.for_institution_id || null,
                  description: nu.description,
                  url: url,
                  accepting_students: accStr
                },
                reason: reason
              }
            });
          }
        }
      } else if (saveKind === 'fact') {
        var curF = fact(id);
        var val = valOf('value');
        var vf = valOf('from') || TODAY;
        if (!val || val === curF.value) { E.formErr = 'Enter a new figure value.'; renderView(); return; }
        E.facts[id] = { value: val, valid_from: vf, last_verified: TODAY };
        log('Figure', id, curF.label, curF.value + (curF.unit ? ' ' + curF.unit : ''), val + (curF.unit ? ' ' + curF.unit : '') + ' from ' + nice(vf), 'core', reason, {
          subpath: '/fact',
          body: { payload: { fact_key: id, label: curF.label, value: val, unit: curF.unit, source_id: curF.source || 'official', valid_from: vf }, reason: reason }
        });
      } else if (saveKind === 'step') {
        var curSt = step(id);
        var stNu = { title: valOf('title'), summary: valOf('summary'), how_to: valOf('how_to') };
        E.steps[id] = Object.assign({}, E.steps[id], stNu);
        E.checked['step:' + id] = TODAY;
        log('Step', id, stNu.title, curSt.summary, stNu.summary, 'core', reason, null);
      }

      E.open = null;
      renderView();
    });
  }

  function boot() {
    wireEvents();
    var token = null;
    try { token = sessionStorage.getItem(STAFF_TOKEN_KEY); } catch (_) {}
    if (token && window.location.protocol !== 'file:' && !/[?&]demo=1(?:&|$)/.test(window.location.search)) {
      loadLiveEditor(false);
    } else {
      renderView();
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
