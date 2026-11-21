// Copyright (c) 2026 Eirini Konidari. All rights reserved.
/* Netherlanded analytics dashboard.
   Reads one JSON document of already-suppressed aggregates.
   No cookies, no credentials, no third-party code, no HTML injection. */

var FALLBACK_ENDPOINT = '/api/stats';
var TIMEOUT_MS = 10000;
var STAFF_TOKEN_KEY = 'nl-staff-jwt';

var REASON_TEXT = {
  floor: 'fewer than fifteen people in this group',
  delta: 'the change since the last release is too small to report',
  sticky: 'withheld in a recent release',
  complementary: 'withheld so a neighbouring figure cannot be worked out',
  over_suppression: 'withheld to keep the release consistent'
};

function make(tag, className, text) {
  var node = document.createElement(tag);
  if (className) { node.className = className; }
  if (text !== undefined && text !== null) { node.textContent = String(text); }
  return node;
}

function uniqueInOrder(values) {
  var seen = Object.create(null);
  var out = [];
  for (var i = 0; i < values.length; i += 1) {
    var key = String(values[i]);
    if (!Object.prototype.hasOwnProperty.call(seen, key)) {
      seen[key] = true;
      out.push(key);
    }
  }
  return out;
}

function cellKey(row, col) { return JSON.stringify([String(row), String(col)]); }

function fmtRate(rate, num, denom, rateDisplay) {
  if (typeof rateDisplay === 'string' && rateDisplay.length) {
    return rateDisplay;
  }
  if (rate === '' || rate === null || rate === undefined) { return 'n/a'; }
  var r = Number(rate);
  if (!Number.isFinite(r)) { return 'n/a'; }
  if (r < 0) { r = 0; }
  if (r > 1) { r = 1; }

  var hasCounts = (num !== '' && num !== null && num !== undefined &&
                   denom !== '' && denom !== null && denom !== undefined);
  var n = hasCounts ? Number(num) : NaN;
  var d = hasCounts ? Number(denom) : NaN;
  var validCounts = Number.isFinite(n) && Number.isFinite(d) && d > 0;

  if ((validCounts && d >= 15 && n < 5) || r <= 0.10) { return '<= 10.0%'; }
  if ((validCounts && d >= 15 && (d - n) < 5) || r >= 0.90) { return '>= 90.0%'; }
  if (validCounts && d < 50) {
    return (Math.round(r * 20) * 5) + '%';
  }
  return Math.round(r * 100) + '%';
}

function reasonText(reason) {
  if (reason && Object.prototype.hasOwnProperty.call(REASON_TEXT, reason)) {
    return REASON_TEXT[reason];
  }
  return 'withheld for privacy';
}

function renderTable(table) {
  var section = make('section', 'nl-table');
  section.appendChild(make('h2', null, table.title || table.table_id));

  var cells = Array.isArray(table.cells) ? table.cells : [];
  var withheld = Array.isArray(table.withheld) ? table.withheld : [];

  if (!cells.length && !withheld.length) {
    section.appendChild(make('p', 'nl-empty',
      'Not enough data yet. Figures appear once at least fifteen people share a group.'));
    return section;
  }

  if (!cells.length) {
    section.appendChild(make('p', 'nl-empty',
      'Not enough data yet. Figures appear once at least fifteen people share a group.'));
  }

  var allEntries = cells.concat(withheld);
  var rows = uniqueInOrder(allEntries.map(function (c) { return c.row; }));
  var cols = uniqueInOrder(allEntries.map(function (c) { return c.col; }));
  var labels = Object.create(null);

  allEntries.forEach(function (c) {
    if (!labels['r:' + c.row]) { labels['r:' + c.row] = c.row_label || c.row; }
    if (!labels['c:' + c.col]) { labels['c:' + c.col] = c.col_label || c.col; }
  });

  var index = Object.create(null);
  cells.forEach(function (c) { index[cellKey(c.row, c.col)] = c; });
  var hidden = Object.create(null);
  withheld.forEach(function (c) { hidden[cellKey(c.row, c.col)] = c; });

  var grid = document.createElement('table');
  grid.className = 'nl-grid';
  var thead = document.createElement('thead');
  var headRow = document.createElement('tr');
  headRow.appendChild(make('th', 'nl-corner', table.row_axis || ''));
  cols.forEach(function (col) {
    headRow.appendChild(make('th', null, labels['c:' + col] || col));
  });
  thead.appendChild(headRow);
  grid.appendChild(thead);

  var tbody = document.createElement('tbody');
  rows.forEach(function (row) {
    var tr = document.createElement('tr');
    tr.appendChild(make('th', null, labels['r:' + row] || row));
    cols.forEach(function (col) {
      var td = document.createElement('td');
      var c = index[cellKey(row, col)];
      var h = hidden[cellKey(row, col)];
      if (c) {
        td.appendChild(make('span', 'nl-rate', fmtRate(c.rate, c.num, c.denom, c.rate_display)));
        if (c.denom !== null && c.denom !== undefined && Number.isFinite(Number(c.denom))) {
          td.appendChild(make('span', 'nl-n', 'n=' + c.denom));
        }
      } else if (h) {
        var label = h.bucket ? 'hidden (' + h.bucket + ')' : 'hidden';
        td.appendChild(make('span', 'nl-hidden', label));
        td.title = reasonText(h.reason);
      } else {
        td.appendChild(make('span', 'nl-none', '-'));
      }
      tr.appendChild(td);
    });
    tbody.appendChild(tr);
  });
  grid.appendChild(tbody);
  section.appendChild(grid);

  if (withheld.length) {
    var reasons = Object.create(null);
    withheld.forEach(function (c) {
      var label = reasonText(c.reason);
      reasons[label] = (reasons[label] || 0) + 1;
    });
    var parts = Object.keys(reasons).map(function (k) {
      return reasons[k] + ' ' + k;
    });
    section.appendChild(make('p', 'nl-note',
      withheld.length + ' of ' + (cells.length + withheld.length) +
      ' groups withheld for privacy (' + parts.join('; ') + ').'));
  }

  return section;
}

function render(root, data) {
  while (root.firstChild) { root.removeChild(root.firstChild); }

  var meta = data && data.meta ? data.meta : {};
  var tables = data && Array.isArray(data.tables) ? data.tables : [];

  if (meta.state === 'empty' || !tables.length) {
    root.appendChild(make('p', 'nl-empty',
      'No statistics have been published yet. Figures appear after the first release.'));
    return;
  }

  if (meta.state === 'withheld' || meta.published_cells === 0) {
    root.appendChild(make('p', 'nl-empty',
      'Not enough data yet. Every group is currently below the reporting threshold.'));
  }

  if (meta.built_at) {
    root.appendChild(make('p', 'nl-stamp', 'Last release: ' + meta.built_at));
  }

  tables.forEach(function (table) { root.appendChild(renderTable(table)); });

  root.appendChild(make('p', 'nl-foot',
    'Counts only, rounded, with small groups withheld. No individual is identifiable ' +
    'from this page, and no data here is linked to any account.'));
}

function loadStats(root) {
  var endpoint = root.getAttribute('data-endpoint') || FALLBACK_ENDPOINT;
  while (root.firstChild) { root.removeChild(root.firstChild); }
  root.appendChild(make('p', 'nl-status', 'Loading statistics...'));

  var token = null;
  try { token = sessionStorage.getItem(STAFF_TOKEN_KEY); } catch (_) {}

  var headers = {};
  if (token) { headers.Authorization = 'Bearer ' + token; }

  var controller = (typeof AbortController === 'function') ? new AbortController() : null;
  var timer = setTimeout(function () {
    if (controller) { controller.abort(); }
  }, TIMEOUT_MS);

  fetch(endpoint, {
    method: 'GET',
    credentials: 'omit',
    referrerPolicy: 'no-referrer',
    cache: 'no-store',
    headers: headers,
    signal: controller ? controller.signal : undefined
  }).then(function (resp) {
    if (resp.status === 401 || resp.status === 403) {
      throw new Error('AUTH_' + resp.status);
    }
    if (!resp.ok) { throw new Error('HTTP ' + resp.status); }
    return resp.json();
  }).then(function (data) {
    clearTimeout(timer);
    render(root, data);
  }).catch(function (err) {
    clearTimeout(timer);
    while (root.firstChild) { root.removeChild(root.firstChild); }
    var msg = (err && (err.message === 'AUTH_401' || err.message === 'AUTH_403'))
      ? 'Sign in or provide a valid university staff token above to load your institution report.'
      : 'Statistics are unavailable right now. Please try again later.';
    root.appendChild(make('p', 'nl-status', msg));
  });
}

function wireAuthForm(root) {
  var form = document.getElementById('nl-auth-form');
  var input = document.getElementById('nl-staff-token');
  var clearBtn = document.getElementById('nl-staff-clear');
  if (!form || !input) { return; }

  form.addEventListener('submit', function (ev) {
    ev.preventDefault();
    var val = String(input.value || '').trim();
    if (!val) { return; }
    try { sessionStorage.setItem(STAFF_TOKEN_KEY, val); } catch (_) {}
    input.value = '';
    loadStats(root);
  });

  if (clearBtn) {
    clearBtn.addEventListener('click', function () {
      try { sessionStorage.removeItem(STAFF_TOKEN_KEY); } catch (_) {}
      input.value = '';
      loadStats(root);
    });
  }
}

function boot() {
  var root = document.getElementById('nl-stats');
  if (!root) { return; }
  wireAuthForm(root);
  loadStats(root);
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', boot);
} else {
  boot();
}
