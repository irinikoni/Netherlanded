// Copyright (c) 2026 Eirini Konidari. All rights reserved.
/* Netherlanded University Dashboard.
   Supports both the v2.1-hardened Demo Preview (proto visual layout with floor >= 15,
   rounding to 5, tail capping) and live authenticated /api/stats JSON snapshots.
   No third-party scripts, no HTML injection, Object.create(null) maps. */
(function () {
  'use strict';

  var FALLBACK_ENDPOINT = '/api/stats';
  var TIMEOUT_MS = 10000;
  var STAFF_TOKEN_KEY = 'nl-staff-jwt';
  var DASH_PREF_KEY = 'nl-dash-v2';

  var REASON_TEXT = {
    floor: 'fewer than fifteen people in this group',
    delta: 'the change since the last release is too small to report',
    sticky: 'withheld in a recent release',
    complementary: 'withheld so a neighbouring figure cannot be worked out',
    over_suppression: 'withheld to keep the release consistent'
  };

  var PHASES = {
    pre_arrival: 'Before travel',
    arrival: 'First weeks',
    first_months: 'Settling in'
  };

  /* Live API fallback schema matching nl.release_json_for_institution() */
  var DEMO_SNAPSHOT = {
    meta: {
      snapshot_id: 12,
      built_at: '2026-11-16T03:00:00Z',
      published: true,
      state: 'ok',
      published_cells: 24,
      withheld: 5,
      institution: 'thuas',
      institution_name: 'The Hague University of Applied Sciences (THUAS)',
      note: 'Demo snapshot: scoped disclosure-controlled aggregates only (floor >= 15, rounded to 5).'
    },
    tables: [
      {
        table_id: 't1_institution_intake',
        title: 'Overall step completion by intake (THUAS)',
        tier: 1,
        row_axis: 'institution',
        col_axis: 'intake',
        metric: 'completed / started',
        cells: [
          { row: 'thuas', row_label: 'THUAS', col: '2026-sep', col_label: 'Sep 2026', num: 1320, denom: 2040, rate: 0.65, band: 65, rate_display: '65%' },
          { row: 'thuas', row_label: 'THUAS', col: '2026-feb', col_label: 'Feb 2026', num: 325, denom: 430, rate: 0.76, band: 75, rate_display: '76%' }
        ],
        withheld: []
      },
      {
        table_id: 't2_inst_step',
        title: 'Journey steps finished, by step (THUAS)',
        tier: 2,
        row_axis: 'inst_step',
        col_axis: 'intake',
        metric: 'completed / started',
        cells: [
          { row: 'thuas:register_gp', row_label: 'Register With A GP', col: '2026-sep', col_label: 'Sep 2026', num: 45, denom: 185, rate: 0.24, band: 25, rate_display: '24%' },
          { row: 'thuas:find_housing', row_label: 'Find Housing With Registrable Address', col: '2026-sep', col_label: 'Sep 2026', num: 95, denom: 210, rate: 0.45, band: 45, rate_display: '45%' },
          { row: 'thuas:register_municipality', row_label: 'Register Municipality & Get BSN', col: '2026-sep', col_label: 'Sep 2026', num: 110, denom: 185, rate: 0.59, band: 60, rate_display: '59%' },
          { row: 'thuas:open_bank', row_label: 'Open Dutch Bank Account', col: '2026-sep', col_label: 'Sep 2026', num: 165, denom: 195, rate: 0.85, band: 85, rate_display: '85%' }
        ],
        withheld: [
          { row: 'thuas:register_gp', row_label: 'Register With A GP', col: '2026-feb', col_label: 'Feb 2026', reason: null, bucket: '5-14' }
        ]
      }
    ]
  };

  /* Rich prototype dataset harmonised to v2.1 SDC rules (min_group=15, counts rounded to 5, tails capped) */
  var DEMO_PROTO = {
    fictional: true,
    generated: '2026-11-16',
    phones: 295,
    counters: 13250,
    min_group: 15,
    institutions: {
      thuas: 'The Hague University of Applied Sciences (THUAS)',
      leiden: 'Leiden University',
      'thuas-zoetermeer': 'THUAS, Zoetermeer campus'
    },
    steps: {
      residence_permit: { title: 'Start your residence permit', phase: 'pre_arrival', optional: false },
      find_housing: { title: 'Find housing you can register at', phase: 'pre_arrival', optional: false },
      check_insurance: { title: 'Arrange student health insurance', phase: 'pre_arrival', optional: false },
      open_bank: { title: 'Open a Dutch bank account', phase: 'pre_arrival', optional: false },
      book_registration: { title: 'Book city hall registration', phase: 'pre_arrival', optional: false },
      plan_finances: { title: 'Check student finance & grants', phase: 'pre_arrival', optional: false },
      register_municipality: { title: 'Register & get your BSN', phase: 'arrival', optional: false },
      collect_permit: { title: 'Pick up your residence permit', phase: 'arrival', optional: false },
      add_bsn_bank: { title: 'Submit your BSN to your bank', phase: 'arrival', optional: false },
      apply_digid: { title: 'Apply for DigiD', phase: 'arrival', optional: false },
      register_gp: { title: 'Register with a local GP (huisarts)', phase: 'arrival', optional: false },
      tb_test: { title: 'Take a TB test (if required)', phase: 'arrival', optional: true },
      find_job: { title: 'Find a part-time job', phase: 'arrival', optional: false },
      dutch_insurance: { title: 'Get Dutch basic health insurance', phase: 'arrival', optional: false },
      student_finance: { title: 'Apply for DUO student finance', phase: 'arrival', optional: false },
      intro_week: { title: 'Join introduction week', phase: 'first_months', optional: true },
      join_community: { title: 'Join a club or Dutch course', phase: 'first_months', optional: true },
      cak_letter: { title: 'Respond to a CAK letter', phase: 'first_months', optional: true },
      wellbeing_checkin: { title: 'Monthly check-in', phase: 'first_months', optional: true }
    },
    summary: [
      { institution_id: 'thuas', region: 'eu_eea', intake_month: '2026-sep', intake_label: 'September 2026 (2026-sep)', students: 140, arrived_pct: null, arrived_display: '>= 90.0%', avg_required_step_completion_pct: 71, gp_registered_pct: 41, missed_registration_deadline_pct: 25 },
      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', intake_label: 'September 2026 (2026-sep)', students: 60, arrived_pct: null, arrived_display: '>= 90.0%', avg_required_step_completion_pct: 76, gp_registered_pct: 36, missed_registration_deadline_pct: 38 },
      { institution_id: 'thuas', region: 'eu_eea', intake_month: '2027-feb', intake_label: 'February 2027 (2027-feb)', students: 14, hidden_under_floor: true },
      { institution_id: 'leiden', region: 'eu_eea', intake_month: '2026-sep', intake_label: 'September 2026 (2026-sep)', students: 45, arrived_pct: null, arrived_display: '>= 90.0%', avg_required_step_completion_pct: 59, gp_registered_pct: 40, missed_registration_deadline_pct: 34 },
      { institution_id: 'leiden', region: 'non_eu', intake_month: '2026-sep', intake_label: 'September 2026 (2026-sep)', students: 20, arrived_pct: null, arrived_display: '>= 90.0%', avg_required_step_completion_pct: 61, gp_registered_pct: 52, missed_registration_deadline_pct: 38 }
    ],
    step_completion: [
      /* THUAS EU/EEA 2026-sep (rounded n=140) */
      { institution_id: 'thuas', region: 'eu_eea', intake_month: '2026-sep', phase: 'pre_arrival', sort_order: 20, step_id: 'find_housing', title: 'Find housing you can register at', students_with_step: 140, completed_pct: null, completed_display: '>= 90.0%', on_time_pct: null, on_time_display: '>= 90.0%', opened_pct: null },
      { institution_id: 'thuas', region: 'eu_eea', intake_month: '2026-sep', phase: 'pre_arrival', sort_order: 30, step_id: 'check_insurance', title: 'Arrange student health insurance', students_with_step: 140, completed_pct: 83, on_time_pct: null, on_time_display: '>= 90.0%', opened_pct: null, opened_display: '>= 90.0%' },
      { institution_id: 'thuas', region: 'eu_eea', intake_month: '2026-sep', phase: 'pre_arrival', sort_order: 40, step_id: 'open_bank', title: 'Open a Dutch bank account', students_with_step: 140, completed_pct: null, completed_display: '>= 90.0%', on_time_pct: null, on_time_display: '>= 90.0%', opened_pct: null, opened_display: '>= 90.0%' },
      { institution_id: 'thuas', region: 'eu_eea', intake_month: '2026-sep', phase: 'pre_arrival', sort_order: 50, step_id: 'book_registration', title: 'Book city hall registration', students_with_step: 140, completed_pct: 85, on_time_pct: 68, opened_pct: null, opened_display: '>= 90.0%' },
      { institution_id: 'thuas', region: 'eu_eea', intake_month: '2026-sep', phase: 'pre_arrival', sort_order: 60, step_id: 'plan_finances', title: 'Check student finance & grants', students_with_step: 140, completed_pct: 60, on_time_pct: null, on_time_display: '>= 90.0%', opened_pct: null, opened_display: '>= 90.0%' },
      { institution_id: 'thuas', region: 'eu_eea', intake_month: '2026-sep', phase: 'arrival', sort_order: 70, step_id: 'register_municipality', title: 'Register & get your BSN', students_with_step: 140, completed_pct: null, completed_display: '>= 90.0%', on_time_pct: 78, opened_pct: null },
      { institution_id: 'thuas', region: 'eu_eea', intake_month: '2026-sep', phase: 'arrival', sort_order: 80, step_id: 'add_bsn_bank', title: 'Submit your BSN to your bank', students_with_step: 140, completed_pct: 63, on_time_pct: 72, opened_pct: 86 },
      { institution_id: 'thuas', region: 'eu_eea', intake_month: '2026-sep', phase: 'arrival', sort_order: 90, step_id: 'apply_digid', title: 'Apply for DigiD', students_with_step: 140, completed_pct: 60, on_time_pct: 86, opened_pct: null, opened_display: '>= 90.0%' },
      { institution_id: 'thuas', region: 'eu_eea', intake_month: '2026-sep', phase: 'arrival', sort_order: 100, step_id: 'register_gp', title: 'Register with a local GP (huisarts)', students_with_step: 140, completed_pct: 41, on_time_pct: 29, opened_pct: 85 },
      { institution_id: 'thuas', region: 'eu_eea', intake_month: '2026-sep', phase: 'arrival', sort_order: 110, step_id: 'find_job', title: 'Find a part-time job', students_with_step: 65, completed_pct: 58, on_time_pct: null, opened_pct: null },
      { institution_id: 'thuas', region: 'eu_eea', intake_month: '2026-sep', phase: 'arrival', sort_order: 120, step_id: 'dutch_insurance', title: 'Get Dutch basic health insurance', students_with_step: 65, completed_pct: 80, on_time_pct: 69, opened_pct: null },
      { institution_id: 'thuas', region: 'eu_eea', intake_month: '2026-sep', phase: 'arrival', sort_order: 130, step_id: 'student_finance', title: 'Apply for DUO student finance', students_with_step: 65, completed_pct: 37, on_time_pct: null, opened_pct: 85 },
      { institution_id: 'thuas', region: 'eu_eea', intake_month: '2026-sep', phase: 'first_months', sort_order: 150, step_id: 'intro_week', title: 'Join introduction week', students_with_step: 140, completed_pct: 80, on_time_pct: null, on_time_display: '>= 90.0%', opened_pct: null, opened_display: '>= 90.0%' },
      { institution_id: 'thuas', region: 'eu_eea', intake_month: '2026-sep', phase: 'first_months', sort_order: 160, step_id: 'join_community', title: 'Join a club or Dutch course', students_with_step: 140, completed_pct: 42, on_time_pct: null, on_time_display: '>= 90.0%', opened_pct: 83 },
      { institution_id: 'thuas', region: 'eu_eea', intake_month: '2026-sep', phase: 'first_months', sort_order: 165, step_id: 'cak_letter', title: 'Respond to a CAK letter', students_with_step: 140, completed_pct: 38, on_time_pct: 87, opened_pct: 75 },
      { institution_id: 'thuas', region: 'eu_eea', intake_month: '2026-sep', phase: 'first_months', sort_order: 170, step_id: 'wellbeing_checkin', title: 'Monthly check-in', students_with_step: 140, completed_pct: 30, on_time_pct: 88, opened_pct: 75 },

      /* THUAS Non-EU 2026-sep (rounded n=60) */
      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', phase: 'pre_arrival', sort_order: 10, step_id: 'residence_permit', title: 'Start your residence permit', students_with_step: 60, completed_pct: null, completed_display: '>= 90.0%', on_time_pct: 87, opened_pct: null, opened_display: '>= 90.0%' },
      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', phase: 'pre_arrival', sort_order: 20, step_id: 'find_housing', title: 'Find housing you can register at', students_with_step: 60, completed_pct: null, completed_display: '>= 90.0%', on_time_pct: null, opened_pct: null },
      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', phase: 'pre_arrival', sort_order: 30, step_id: 'check_insurance', title: 'Arrange student health insurance', students_with_step: 60, completed_pct: 89, on_time_pct: null, opened_pct: null },
      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', phase: 'pre_arrival', sort_order: 40, step_id: 'open_bank', title: 'Open a Dutch bank account', students_with_step: 60, completed_pct: 89, on_time_pct: null, opened_pct: null },
      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', phase: 'pre_arrival', sort_order: 50, step_id: 'book_registration', title: 'Book city hall registration', students_with_step: 60, completed_pct: 89, on_time_pct: 57, opened_pct: null },
      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', phase: 'pre_arrival', sort_order: 60, step_id: 'plan_finances', title: 'Check student finance & grants', students_with_step: 60, completed_pct: 62, on_time_pct: null, opened_pct: 84 },
      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', phase: 'arrival', sort_order: 70, step_id: 'register_municipality', title: 'Register & get your BSN', students_with_step: 60, completed_pct: 87, on_time_pct: 72, opened_pct: null },
      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', phase: 'arrival', sort_order: 75, step_id: 'collect_permit', title: 'Pick up your residence permit', students_with_step: 60, completed_pct: 87, on_time_pct: 89, opened_pct: null },
      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', phase: 'arrival', sort_order: 80, step_id: 'add_bsn_bank', title: 'Submit your BSN to your bank', students_with_step: 60, completed_pct: 70, on_time_pct: 72, opened_pct: null, opened_display: '>= 90.0%' },
      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', phase: 'arrival', sort_order: 90, step_id: 'apply_digid', title: 'Apply for DigiD', students_with_step: 60, completed_pct: 67, on_time_pct: null, opened_pct: null, opened_display: '>= 90.0%' },
      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', phase: 'arrival', sort_order: 100, step_id: 'register_gp', title: 'Register with a local GP (huisarts)', students_with_step: 60, completed_pct: 36, on_time_pct: 55, opened_pct: 84 },
      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', phase: 'arrival', sort_order: 105, step_id: 'tb_test', title: 'Take a TB test (if required)', students_with_step: 60, completed_pct: 48, on_time_pct: null, on_time_display: '>= 90.0%', opened_pct: 79 },
      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', phase: 'arrival', sort_order: 110, step_id: 'find_job', title: 'Find a part-time job', students_with_step: 35, completed_pct: 62, on_time_pct: null, on_time_display: '>= 90.0%', opened_pct: null },
      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', phase: 'arrival', sort_order: 120, step_id: 'dutch_insurance', title: 'Get Dutch basic health insurance', students_with_step: 35, completed_pct: 59, on_time_pct: 73, opened_pct: null },
      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', phase: 'first_months', sort_order: 150, step_id: 'intro_week', title: 'Join introduction week', students_with_step: 60, completed_pct: 80, on_time_pct: 86, opened_pct: null },
      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', phase: 'first_months', sort_order: 160, step_id: 'join_community', title: 'Join a club or Dutch course', students_with_step: 60, completed_pct: 43, on_time_pct: null, opened_pct: 82 },
      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', phase: 'first_months', sort_order: 165, step_id: 'cak_letter', title: 'Respond to a CAK letter', students_with_step: 60, completed_pct: 46, on_time_pct: null, opened_pct: 84 },
      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', phase: 'first_months', sort_order: 170, step_id: 'wellbeing_checkin', title: 'Monthly check-in', students_with_step: 60, completed_pct: 23, on_time_pct: null, opened_pct: 82 },

      /* Leiden EU/EEA 2026-sep (rounded n=45 -> multiples of 5% bands) */
      { institution_id: 'leiden', region: 'eu_eea', intake_month: '2026-sep', phase: 'pre_arrival', sort_order: 20, step_id: 'find_housing', title: 'Find housing you can register at', students_with_step: 45, completed_pct: null, on_time_pct: 89, opened_pct: null },
      { institution_id: 'leiden', region: 'eu_eea', intake_month: '2026-sep', phase: 'pre_arrival', sort_order: 30, step_id: 'check_insurance', title: 'Arrange student health insurance', students_with_step: 45, completed_pct: 85, on_time_pct: 85, opened_pct: null },
      { institution_id: 'leiden', region: 'eu_eea', intake_month: '2026-sep', phase: 'pre_arrival', sort_order: 40, step_id: 'open_bank', title: 'Open a Dutch bank account', students_with_step: 45, completed_pct: null, on_time_pct: 85, opened_pct: null, opened_display: '>= 90.0%' },
      { institution_id: 'leiden', region: 'eu_eea', intake_month: '2026-sep', phase: 'pre_arrival', sort_order: 50, step_id: 'book_registration', title: 'Book city hall registration', students_with_step: 45, completed_pct: null, on_time_pct: 60, opened_pct: null, opened_display: '>= 90.0%' },
      { institution_id: 'leiden', region: 'eu_eea', intake_month: '2026-sep', phase: 'pre_arrival', sort_order: 60, step_id: 'plan_finances', title: 'Check student finance & grants', students_with_step: 45, completed_pct: 65, on_time_pct: null, opened_pct: null },
      { institution_id: 'leiden', region: 'eu_eea', intake_month: '2026-sep', phase: 'arrival', sort_order: 70, step_id: 'register_municipality', title: 'Register & get your BSN', students_with_step: 45, completed_pct: null, on_time_pct: 70, opened_pct: null, opened_display: '>= 90.0%' },
      { institution_id: 'leiden', region: 'eu_eea', intake_month: '2026-sep', phase: 'arrival', sort_order: 80, step_id: 'add_bsn_bank', title: 'Submit your BSN to your bank', students_with_step: 45, completed_pct: 65, on_time_pct: null, opened_pct: null, opened_display: '>= 90.0%' },
      { institution_id: 'leiden', region: 'eu_eea', intake_month: '2026-sep', phase: 'arrival', sort_order: 90, step_id: 'apply_digid', title: 'Apply for DigiD', students_with_step: 45, completed_pct: 55, on_time_pct: null, opened_pct: 85 },
      { institution_id: 'leiden', region: 'eu_eea', intake_month: '2026-sep', phase: 'arrival', sort_order: 100, step_id: 'register_gp', title: 'Register with a local GP (huisarts)', students_with_step: 45, completed_pct: 40, on_time_pct: 25, opened_pct: 85 },
      { institution_id: 'leiden', region: 'eu_eea', intake_month: '2026-sep', phase: 'arrival', sort_order: 110, step_id: 'find_job', title: 'Find a part-time job', students_with_step: 25, completed_pct: 65, on_time_pct: null, opened_pct: null },
      { institution_id: 'leiden', region: 'eu_eea', intake_month: '2026-sep', phase: 'arrival', sort_order: 120, step_id: 'dutch_insurance', title: 'Get Dutch basic health insurance', students_with_step: 25, completed_pct: null, on_time_pct: 75, opened_pct: null, opened_display: '>= 90.0%' },
      { institution_id: 'leiden', region: 'eu_eea', intake_month: '2026-sep', phase: 'arrival', sort_order: 130, step_id: 'student_finance', title: 'Apply for DUO student finance', students_with_step: 25, completed_pct: 30, on_time_pct: null, opened_pct: null },

      /* Leiden Non-EU 2026-sep (rounded n=20 -> multiples of 5% bands) */
      { institution_id: 'leiden', region: 'non_eu', intake_month: '2026-sep', phase: 'pre_arrival', sort_order: 10, step_id: 'residence_permit', title: 'Start your residence permit', students_with_step: 20, completed_pct: null, on_time_pct: 70, opened_pct: null, opened_display: '>= 90.0%' },
      { institution_id: 'leiden', region: 'non_eu', intake_month: '2026-sep', phase: 'pre_arrival', sort_order: 20, step_id: 'find_housing', title: 'Find housing you can register at', students_with_step: 20, completed_pct: null, on_time_pct: null, opened_pct: null, opened_display: '>= 90.0%' },
      { institution_id: 'leiden', region: 'non_eu', intake_month: '2026-sep', phase: 'pre_arrival', sort_order: 30, step_id: 'check_insurance', title: 'Arrange student health insurance', students_with_step: 20, completed_pct: 65, on_time_pct: null, on_time_display: '>= 90.0%', opened_pct: null },
      { institution_id: 'leiden', region: 'non_eu', intake_month: '2026-sep', phase: 'pre_arrival', sort_order: 40, step_id: 'open_bank', title: 'Open a Dutch bank account', students_with_step: 20, completed_pct: 75, on_time_pct: null, opened_pct: null, opened_display: '>= 90.0%' },
      { institution_id: 'leiden', region: 'non_eu', intake_month: '2026-sep', phase: 'arrival', sort_order: 80, step_id: 'add_bsn_bank', title: 'Submit your BSN to your bank', students_with_step: 20, completed_pct: 60, on_time_pct: 60, opened_pct: null },
      { institution_id: 'leiden', region: 'non_eu', intake_month: '2026-sep', phase: 'arrival', sort_order: 90, step_id: 'apply_digid', title: 'Apply for DigiD', students_with_step: 20, completed_pct: 55, on_time_pct: null, on_time_display: '>= 90.0%', opened_pct: null },
      { institution_id: 'leiden', region: 'non_eu', intake_month: '2026-sep', phase: 'arrival', sort_order: 100, step_id: 'register_gp', title: 'Register with a local GP (huisarts)', students_with_step: 20, completed_pct: 50, on_time_pct: null, opened_pct: 75 },
      { institution_id: 'leiden', region: 'non_eu', intake_month: '2026-sep', phase: 'arrival', sort_order: 110, step_id: 'find_job', title: 'Find a part-time job', students_with_step: 15, completed_pct: 45, on_time_pct: null, opened_pct: 65 }
    ],
    deadline_missed: [
      { institution_id: 'thuas', region: 'eu_eea', intake_month: '2026-sep', step_id: 'register_gp', label: 'Register with a GP in your first 2 weeks', severity: 'advice', students_with_deadline: 140, missed_pct: 84 },
      { institution_id: 'thuas', region: 'eu_eea', intake_month: '2026-sep', step_id: 'cak_letter', label: 'Respond to CAK letter to avoid a fine', severity: 'financial', students_with_deadline: 140, missed_pct: 57 },
      { institution_id: 'thuas', region: 'eu_eea', intake_month: '2026-sep', step_id: 'add_bsn_bank', label: 'Add BSN to bank account (90–120 days)', severity: 'financial', students_with_deadline: 140, missed_pct: 48 },
      { institution_id: 'thuas', region: 'eu_eea', intake_month: '2026-sep', step_id: 'dutch_insurance', label: 'Dutch health insurance starts today', severity: 'legal', students_with_deadline: 65, missed_pct: 43 },
      { institution_id: 'thuas', region: 'eu_eea', intake_month: '2026-sep', step_id: 'book_registration', label: 'Book city hall appointment before travel', severity: 'advice', students_with_deadline: 140, missed_pct: 40 },
      { institution_id: 'thuas', region: 'eu_eea', intake_month: '2026-sep', step_id: 'register_municipality', label: 'Register in person within 5 days', severity: 'legal', students_with_deadline: 140, missed_pct: 25 },

      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', step_id: 'register_gp', label: 'Register with a GP in your first 2 weeks', severity: 'advice', students_with_deadline: 60, missed_pct: 70 },
      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', step_id: 'cak_letter', label: 'Respond to CAK letter to avoid a fine', severity: 'financial', students_with_deadline: 60, missed_pct: 59 },
      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', step_id: 'book_registration', label: 'Book city hall appointment before travel', severity: 'advice', students_with_deadline: 60, missed_pct: 49 },
      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', step_id: 'dutch_insurance', label: 'Dutch health insurance starts today', severity: 'legal', students_with_deadline: 35, missed_pct: 46 },
      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', step_id: 'add_bsn_bank', label: 'Add BSN to bank account (90–120 days)', severity: 'financial', students_with_deadline: 60, missed_pct: 46 },
      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', step_id: 'register_municipality', label: 'Register in person within 5 days', severity: 'legal', students_with_deadline: 60, missed_pct: 38 },
      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', step_id: 'residence_permit', label: 'Submit permit documents before summer', severity: 'advice', students_with_deadline: 60, missed_pct: 13 },

      { institution_id: 'leiden', region: 'eu_eea', intake_month: '2026-sep', step_id: 'register_gp', label: 'Register with a GP in your first 2 weeks', severity: 'advice', students_with_deadline: 45, missed_pct: 80 },
      { institution_id: 'leiden', region: 'eu_eea', intake_month: '2026-sep', step_id: 'cak_letter', label: 'Respond to CAK letter to avoid a fine', severity: 'financial', students_with_deadline: 45, missed_pct: 55 },
      { institution_id: 'leiden', region: 'eu_eea', intake_month: '2026-sep', step_id: 'register_municipality', label: 'Register in person within 5 days', severity: 'legal', students_with_deadline: 45, missed_pct: 35 },

      { institution_id: 'leiden', region: 'non_eu', intake_month: '2026-sep', step_id: 'cak_letter', label: 'Respond to CAK letter to avoid a fine', severity: 'financial', students_with_deadline: 20, missed_pct: 75 },
      { institution_id: 'leiden', region: 'non_eu', intake_month: '2026-sep', step_id: 'register_gp', label: 'Register with a GP in your first 2 weeks', severity: 'advice', students_with_deadline: 20, missed_pct: 70 },
      { institution_id: 'leiden', region: 'non_eu', intake_month: '2026-sep', step_id: 'register_municipality', label: 'Register in person within 5 days', severity: 'legal', students_with_deadline: 20, missed_pct: 40 }
    ],
    scam_exposure: [
      { institution_id: 'thuas', region: 'eu_eea', intake_month: '2026-sep', students: 140, checks: 160, high_risk_pct: 30 },
      { institution_id: 'thuas', region: 'non_eu', intake_month: '2026-sep', students: 60, checks: 85, high_risk_pct: 23 },
      { institution_id: 'leiden', region: 'eu_eea', intake_month: '2026-sep', students: 45, checks: 50, high_risk_pct: 15 },
      { institution_id: 'leiden', region: 'non_eu', intake_month: '2026-sep', students: 20, checks: 20, high_risk_pct: null }
    ]
  };

  var state = {
    mode: 'demo',
    inst: 'thuas',
    month: '2026-sep',
    region: 'eu_eea',
    liveData: null,
    liveIntake: 'all'
  };

  try {
    var saved = JSON.parse(localStorage.getItem(DASH_PREF_KEY) || 'null');
    if (saved && DEMO_PROTO.institutions[saved.inst]) {
      state.inst = saved.inst;
      state.region = saved.region === 'non_eu' ? 'non_eu' : 'eu_eea';
    }
  } catch (_) {}

  function savePrefs() {
    try {
      localStorage.setItem(DASH_PREF_KEY, JSON.stringify({ inst: state.inst, region: state.region }));
    } catch (_) {}
  }

  function make(tag, className, text) {
    var node = document.createElement(tag);
    if (className) { node.className = className; }
    if (text !== undefined && text !== null) { node.textContent = String(text); }
    return node;
  }

  function clearChildren(node) {
    while (node && node.firstChild) { node.removeChild(node.firstChild); }
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

  function hiddenBadge(titleText, labelText) {
    var span = make('span', 'hid', labelText || 'hidden');
    var msg = titleText || 'Withheld under floor >= 15 / tail-guard rule';
    span.title = msg;
    span.setAttribute('aria-label', (labelText || 'hidden') + ' — ' + msg);
    return span;
  }

  function makeTile(k, valNodeOrText, d) {
    var tile = make('div', 'tile');
    tile.appendChild(make('span', 'k', k));
    var v = make('span', 'v');
    if (valNodeOrText === null || valNodeOrText === undefined) {
      v.appendChild(hiddenBadge('Built on fewer than 5 students or below reporting threshold'));
    } else if (typeof valNodeOrText === 'object') {
      v.appendChild(valNodeOrText);
    } else {
      v.textContent = String(valNodeOrText);
    }
    tile.appendChild(v);
    if (d) { tile.appendChild(make('span', 'd', d)); }
    return tile;
  }

  function makeMeter(pct, disp, soft, title) {
    var wrap = make('div', 'meter');
    var hasDisp = typeof disp === 'string' && disp.length > 0;
    if ((pct === null || pct === undefined) && !hasDisp) {
      wrap.appendChild(make('span', 'track'));
      var hb = make('b', 'hid', 'hidden');
      hb.title = 'Built on fewer than 5 students, so it is hidden';
      wrap.appendChild(hb);
      return wrap;
    }
    var safePct;
    if (hasDisp && disp.indexOf('<=') === 0) {
      safePct = 10;
    } else if (hasDisp && disp.indexOf('>=') === 0) {
      safePct = 90;
    } else {
      safePct = Math.max(0, Math.min(100, Number(pct) || 0));
    }
    var textDisp = hasDisp ? disp : (safePct >= 90 ? '>= 90.0%' : (safePct <= 10 ? '<= 10.0%' : safePct + '%'));
    wrap.title = (title || 'Rate') + ': ' + textDisp;
    var track = make('span', 'track');
    var fill = make('span', 'fill' + (soft ? ' soft' : ''));
    fill.style.width = safePct + '%';
    track.appendChild(fill);
    wrap.appendChild(track);
    wrap.appendChild(make('b', null, textDisp));
    return wrap;
  }

  function csvSafe(val) {
    var s = String(val === null || val === undefined ? '' : val);
    if (/^[=+\-@\t\r]/.test(s)) { s = "'" + s; }
    return '"' + s.replace(/"/g, '""') + '"';
  }

  function exportCsv(rows, filename) {
    var csv = rows.map(function (r) { return r.map(csvSafe).join(','); }).join('\r\n');
    var blob = new Blob([csv], { type: 'text/csv;charset=utf-8' });
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
  }

  function renderDemo() {
    var root = document.getElementById('nl-stats');
    var stuckHost = document.getElementById('nl-bottlenecks');
    var intakeSel = document.getElementById('nl-intake-filter');
    var upd = document.getElementById('upd');
    var banner = document.getElementById('nl-mode-banner');
    if (!root) { return; }

    clearChildren(root);
    if (stuckHost) { clearChildren(stuckHost); stuckHost.hidden = true; }
    savePrefs();

    if (banner) {
      clearChildren(banner);
      banner.appendChild(make('strong', null, 'Demo data'));
      banner.appendChild(document.createTextNode(' \u00b7 floor \u226515, rounded to 5'));
    }
    if (upd) {
      upd.textContent = 'Release ' + DEMO_PROTO.generated;
    }

    var mySummary = DEMO_PROTO.summary.filter(function (r) { return r.institution_id === state.inst; });
    var months = uniqueInOrder(mySummary.map(function (r) { return r.intake_month; }));
    if (intakeSel) {
      clearChildren(intakeSel);
      if (!months.length) {
        var oNone = make('option', null, 'No intake to show');
        oNone.value = '';
        intakeSel.appendChild(oNone);
        intakeSel.disabled = true;
      } else {
        intakeSel.disabled = false;
        months.forEach(function (m) {
          var lbl = (mySummary.find(function (r) { return r.intake_month === m; }) || {}).intake_label || m;
          var o = make('option', null, lbl);
          o.value = m;
          intakeSel.appendChild(o);
        });
        if (months.indexOf(state.month) === -1) { state.month = months[0]; }
        intakeSel.value = state.month;
      }
    }

    var loginSel = document.getElementById('login');
    if (loginSel) { loginSel.disabled = false; }
    var regWrap = document.getElementById('nl-region-filter-wrap');
    if (regWrap) { regWrap.hidden = false; }
    document.querySelectorAll('[data-region]').forEach(function (b) {
      var active = b.getAttribute('data-region') === state.region;
      b.setAttribute('aria-pressed', String(active));
      b.hidden = false;
    });

    var S = mySummary.find(function (r) {
      return r.intake_month === state.month && r.region === state.region;
    });
    var grpLabel = state.region === 'eu_eea' ? 'EU / EEA' : 'non-EU';
    var instName = DEMO_PROTO.institutions[state.inst] || state.inst;

    if (!S || S.hidden_under_floor || S.students < DEMO_PROTO.min_group) {
      var empty = make('div', 'empty');
      empty.appendChild(make('h2', null, months.length ? 'Nothing to show for ' + grpLabel + ' students in ' + state.month : 'Nothing to show yet'));
      empty.appendChild(make('p', 'sub', 'Fewer than ' + DEMO_PROTO.min_group + ' students — withheld for privacy.'));
      root.appendChild(empty);
      return;
    }

    /* 1. Summary Tiles */
    var sumSec = make('section');
    sumSec.appendChild(make('h2', null, S.intake_label + ', ' + grpLabel + ' students'));
    var tiles = make('div', 'tiles');
    tiles.appendChild(makeTile('Students taking part', 'n=' + S.students, ''));
    tiles.appendChild(makeTile('Arrived', S.arrived_display || (S.arrived_pct !== null ? fmtRate(S.arrived_pct / 100, null, null) : null), ''));
    tiles.appendChild(makeTile('Required steps done', S.avg_required_step_completion_pct + '%', ''));
    tiles.appendChild(makeTile('Registered with a GP', S.gp_registered_pct + '%', ''));
    tiles.appendChild(makeTile('Missed 5-day registration', S.missed_registration_deadline_pct + '%', ''));
    sumSec.appendChild(tiles);
    root.appendChild(sumSec);

    /* 2. Where students get stuck (top 3 lowest required steps) */
    var steps = DEMO_PROTO.step_completion.filter(function (r) {
      return r.institution_id === state.inst && r.intake_month === state.month && r.region === state.region;
    }).sort(function (a, b) { return a.sort_order - b.sort_order; });

    var stuck = steps.filter(function (r) {
      var meta = DEMO_PROTO.steps[r.step_id];
      return meta && !meta.optional && (r.completed_pct !== null || r.completed_display === '<= 10.0%');
    }).sort(function (a, b) {
      var av = a.completed_pct !== null ? a.completed_pct : 10;
      var bv = b.completed_pct !== null ? b.completed_pct : 10;
      return av - bv;
    }).slice(0, 3);

    if (stuckHost && stuck.length) {
      stuckHost.appendChild(make('h2', null, 'Where students get stuck'));
      var sg = make('div', 'stuck');
      stuck.forEach(function (r) {
        var tile = make('div', 'tile');
        tile.appendChild(make('span', 'k', PHASES[r.phase] || r.phase));
        tile.appendChild(make('span', 't', r.title));
        tile.appendChild(make('span', 'v', r.completed_display || (r.completed_pct + '%')));
        tile.appendChild(make('span', 'd', 'n=' + r.students_with_step));
        sg.appendChild(tile);
      });
      stuckHost.appendChild(sg);
      stuckHost.hidden = false;
    }

    /* 3. Every step table */
    var stepSec = make('section');
    stepSec.appendChild(make('h2', null, 'Every step'));
    var card = make('div', 'card');
    var curPhase = null;
    steps.forEach(function (r) {
      if (r.phase !== curPhase) {
        curPhase = r.phase;
        card.appendChild(make('div', 'phase', PHASES[curPhase] || curPhase));
        var head = make('div', 'row head');
        head.appendChild(make('span', 't', 'Step'));
        head.appendChild(make('span', null, 'Finished'));
        head.appendChild(make('span', 'n', 'On time'));
        head.appendChild(make('span', 'n', 'Opened'));
        card.appendChild(head);
      }
      var row = make('div', 'row');
      var titleCol = make('span', 't', r.title + (DEMO_PROTO.steps[r.step_id] && DEMO_PROTO.steps[r.step_id].optional ? ' (optional)' : ''));
      titleCol.appendChild(make('small', null, 'n=' + r.students_with_step));
      row.appendChild(titleCol);
      row.appendChild(makeMeter(r.completed_pct, r.completed_display, false, 'Finished'));

      var otCell = make('span', 'n');
      if (r.on_time_display) {
        otCell.textContent = r.on_time_display;
      } else if (r.on_time_pct === null || r.on_time_pct === undefined) {
        otCell.appendChild(hiddenBadge('No deadline or below 5-student disclosure threshold', '–'));
      } else {
        otCell.textContent = r.on_time_pct + '%';
      }
      row.appendChild(otCell);

      var opCell = make('span', 'n');
      if (r.opened_display) {
        opCell.textContent = r.opened_display;
      } else if (r.opened_pct === null || r.opened_pct === undefined) {
        opCell.appendChild(hiddenBadge('Withheld under floor/tail rule'));
      } else {
        opCell.textContent = r.opened_pct + '%';
      }
      row.appendChild(opCell);
      card.appendChild(row);
    });

    var foot = make('div', 'bar-foot');
    var copyBtn = make('button', 'btn', 'Copy this table');
    copyBtn.type = 'button';
    var statusSpan = make('span');
    copyBtn.addEventListener('click', function () {
      var tsv = ['Step\tPhase\tStudents\tFinished %\tOn time %\tOpened %'].concat(steps.map(function (r) {
        return [
          r.title,
          PHASES[r.phase] || r.phase,
          r.students_with_step,
          r.completed_display || (r.completed_pct === null ? 'hidden' : r.completed_pct + '%'),
          r.on_time_display || (r.on_time_pct === null ? '' : r.on_time_pct + '%'),
          r.opened_display || (r.opened_pct === null ? 'hidden' : r.opened_pct + '%')
        ].join('\t');
      })).join('\n');
      try {
        navigator.clipboard.writeText(tsv).then(function () {
          statusSpan.textContent = 'Copied. Paste into Excel or Sheets.';
        }, function () {
          statusSpan.textContent = 'Clipboard blocked here — use Export CSV above.';
        });
      } catch (_) {
        statusSpan.textContent = 'Clipboard blocked here — use Export CSV above.';
      }
    });
    foot.appendChild(copyBtn);
    foot.appendChild(statusSpan);
    card.appendChild(foot);
    stepSec.appendChild(card);
    root.appendChild(stepSec);

    /* 4. Two columns: Missed deadlines & Room scam checks */
    var cols = make('div', 'cols');

    var dls = DEMO_PROTO.deadline_missed.filter(function (r) {
      return r.institution_id === state.inst && r.intake_month === state.month && r.region === state.region;
    }).sort(function (a, b) { return (b.missed_pct || 0) - (a.missed_pct || 0); });
    var dlSec = make('section');
    dlSec.appendChild(make('h2', null, 'Missed deadlines'));
    var dlCard = make('div', 'card');
    if (!dls.length) {
      dlCard.appendChild(make('div', 'row', 'No deadline has passed yet for this intake.'));
    } else {
      dls.forEach(function (r, idx) {
        var row = make('div', 'row');
        row.style.gridTemplateColumns = 'minmax(0,1fr)';
        if (idx === 0) { row.style.borderTop = '0'; }
        var span = make('span', 't');
        var sev = r.severity === 'legal' ? ['must', 'Must'] : (r.severity === 'financial' ? ['fee', 'Fee'] : ['tip', 'Tip']);
        span.appendChild(make('span', 'tag ' + sev[0], sev[1]));
        span.appendChild(document.createTextNode(r.label));
        span.appendChild(make('small', null, 'n=' + r.students_with_deadline));
        row.appendChild(span);
        row.appendChild(makeMeter(r.missed_pct, null, true, 'Missed'));
        dlCard.appendChild(row);
      });
    }
    dlSec.appendChild(dlCard);
    cols.appendChild(dlSec);

    var sc = DEMO_PROTO.scam_exposure.find(function (r) {
      return r.institution_id === state.inst && r.intake_month === state.month && r.region === state.region;
    });
    var scSec = make('section');
    scSec.appendChild(make('h2', null, 'Room scam checks'));
    var scTiles = make('div', 'tiles');
    if (sc) {
      scTiles.appendChild(makeTile('Checks done', 'n=' + sc.checks, ''));
      scTiles.appendChild(makeTile('Ended "high risk"', sc.high_risk_pct === null ? null : (sc.high_risk_pct + '%'), ''));
    } else {
      scTiles.appendChild(makeTile('Scam checks', '—', 'No published checks yet'));
    }
    scSec.appendChild(scTiles);
    cols.appendChild(scSec);

    root.appendChild(cols);
  }

  function renderLiveTable(table, intake) {
    var sec = make('section');
    sec.appendChild(make('h2', null, table.title || table.table_id));

    var cells = Array.isArray(table.cells) ? table.cells : [];
    var withheld = Array.isArray(table.withheld) ? table.withheld : [];
    if (intake && intake !== 'all') {
      cells = cells.filter(function (c) { return String(c.col) === intake; });
      withheld = withheld.filter(function (c) { return String(c.col) === intake; });
    }

    var card = make('div', 'card');
    if (!cells.length && !withheld.length) {
      card.appendChild(make('div', 'row', 'Not enough data yet. Figures appear once at least fifteen people share a group.'));
      sec.appendChild(card);
      return sec;
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
    headRow.appendChild(make('th', null, table.row_axis || ''));
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
          td.appendChild(hiddenBadge(reasonText(h.reason), label));
        } else {
          td.appendChild(make('span', 'opt', '–'));
        }
        tr.appendChild(td);
      });
      tbody.appendChild(tr);
    });
    grid.appendChild(tbody);
    card.appendChild(grid);

    if (withheld.length) {
      var reasons = Object.create(null);
      withheld.forEach(function (c) {
        var label = reasonText(c.reason);
        reasons[label] = (reasons[label] || 0) + 1;
      });
      var parts = Object.keys(reasons).map(function (k) { return reasons[k] + ' ' + k; });
      card.appendChild(make('div', 'bar-foot',
        withheld.length + ' of ' + (cells.length + withheld.length) +
        ' groups withheld for privacy (' + parts.join('; ') + ').'));
    }

    sec.appendChild(card);
    return sec;
  }

  function renderLive(data) {
    var root = document.getElementById('nl-stats');
    var stuckHost = document.getElementById('nl-bottlenecks');
    var intakeSel = document.getElementById('nl-intake-filter');
    var upd = document.getElementById('upd');
    var banner = document.getElementById('nl-mode-banner');
    if (!root) { return; }

    state.liveData = data || DEMO_SNAPSHOT;
    clearChildren(root);
    if (stuckHost) { clearChildren(stuckHost); stuckHost.hidden = true; }

    var meta = state.liveData.meta || {};
    var tables = Array.isArray(state.liveData.tables) ? state.liveData.tables : [];

    if (banner) {
      clearChildren(banner);
      banner.appendChild(make('strong', null, 'Live · '));
      banner.appendChild(document.createTextNode(meta.institution || 'authenticated'));
    }
    if (upd && meta.built_at) {
      upd.textContent = 'Last release: ' + meta.built_at;
    }

    if (intakeSel) {
      var seen = Object.create(null);
      clearChildren(intakeSel);
      var optAll = make('option', null, 'All published intakes');
      optAll.value = 'all';
      intakeSel.appendChild(optAll);
      tables.forEach(function (t) {
        (t.cells || []).concat(t.withheld || []).forEach(function (c) {
          if (c && c.col && !Object.prototype.hasOwnProperty.call(seen, c.col)) {
            seen[c.col] = true;
            var opt = make('option', null, c.col_label || c.col);
            opt.value = c.col;
            intakeSel.appendChild(opt);
          }
        });
      });
      intakeSel.disabled = false;
      intakeSel.value = state.liveIntake;
    }

    var loginSel = document.getElementById('login');
    if (loginSel) { loginSel.disabled = true; }
    var regWrap = document.getElementById('nl-region-filter-wrap');
    if (regWrap) { regWrap.hidden = true; }
    document.querySelectorAll('[data-region]').forEach(function (b) { b.hidden = true; });

    if (meta.state === 'empty' || !tables.length) {
      var empty = make('div', 'empty');
      empty.appendChild(make('h2', null, 'No statistics published yet'));
      empty.appendChild(make('p', 'sub', 'No published snapshot yet.'));
      root.appendChild(empty);
      return;
    }

    tables.forEach(function (t) {
      root.appendChild(renderLiveTable(t, state.liveIntake));
    });
  }

  function loadLive() {
    var root = document.getElementById('nl-stats');
    if (!root) { return; }
    var endpoint = root.getAttribute('data-endpoint') || FALLBACK_ENDPOINT;
    var token = null;
    try { token = sessionStorage.getItem(STAFF_TOKEN_KEY); } catch (_) {}

    if (!token || window.location.protocol === 'file:' || /[?&]demo=1(?:&|$)/.test(window.location.search)) {
      state.mode = 'demo';
      renderDemo();
      if (token && window.location.protocol === 'file:') {
        var bNote = document.getElementById('nl-mode-banner');
        if (bNote) {
          bNote.appendChild(document.createTextNode(' Live /api/stats requires serving over http(s):// (currently file://, showing Demo Mode).'));
        }
      }
      return;
    }

    clearChildren(root);
    root.appendChild(make('div', 'empty', 'Loading live institution statistics...'));

    var controller = (typeof AbortController === 'function') ? new AbortController() : null;
    var timer = setTimeout(function () { if (controller) { controller.abort(); } }, TIMEOUT_MS);

    var url = endpoint;
    var qInst = null;
    try {
      var qp = new URLSearchParams(window.location.search || '');
      qInst = qp.get('institution') || null;
    } catch (_) { qInst = null; }
    if (qInst && url.indexOf('institution=') === -1) {
      url += (url.indexOf('?') === -1 ? '?' : '&') + 'institution=' + encodeURIComponent(qInst);
    }

    fetch(url, {
      method: 'GET',
      credentials: 'omit',
      referrerPolicy: 'no-referrer',
      cache: 'no-store',
      headers: { Authorization: 'Bearer ' + token },
      signal: controller ? controller.signal : undefined
    }).then(function (resp) {
      clearTimeout(timer);
      if (!resp.ok) { throw new Error('HTTP ' + resp.status); }
      return resp.json();
    }).then(function (data) {
      state.mode = 'live';
      renderLive(data);
    }).catch(function () {
      clearTimeout(timer);
      state.mode = 'demo';
      renderDemo();
      var banner = document.getElementById('nl-mode-banner');
      if (banner) {
        clearChildren(banner);
        banner.appendChild(make('strong', null, 'Live API unreachable or token rejected — showing Demo Preview. '));
        banner.appendChild(document.createTextNode('Check your staff Bearer JWT or deploy /api/stats.'));
      }
    });
  }

  function wireEvents() {
    var loginSel = document.getElementById('login');
    var intakeSel = document.getElementById('nl-intake-filter');
    var authForm = document.getElementById('nl-auth-form');
    var tokenInput = document.getElementById('nl-staff-token');
    var clearBtn = document.getElementById('nl-staff-clear');
    var demoBtn = document.getElementById('nl-demo-btn');
    var exportBtn = document.getElementById('nl-export-csv');

    if (loginSel) {
      loginSel.value = state.inst;
      loginSel.addEventListener('change', function () {
        state.inst = loginSel.value;
        state.mode = 'demo';
        renderDemo();
      });
    }

    if (intakeSel) {
      intakeSel.addEventListener('change', function () {
        if (state.mode === 'live') {
          state.liveIntake = intakeSel.value || 'all';
          renderLive(state.liveData);
        } else {
          state.month = intakeSel.value;
          renderDemo();
        }
      });
    }

    document.querySelectorAll('[data-region]').forEach(function (b) {
      b.addEventListener('click', function () {
        state.region = b.getAttribute('data-region') || 'eu_eea';
        renderDemo();
      });
    });

    if (authForm && tokenInput) {
      authForm.addEventListener('submit', function (ev) {
        ev.preventDefault();
        var val = String(tokenInput.value || '').trim();
        if (!val) { return; }
        try { sessionStorage.setItem(STAFF_TOKEN_KEY, val); } catch (_) {}
        tokenInput.value = '';
        loadLive();
      });
    }

    if (clearBtn) {
      clearBtn.addEventListener('click', function () {
        try { sessionStorage.removeItem(STAFF_TOKEN_KEY); } catch (_) {}
        if (tokenInput) { tokenInput.value = ''; }
        state.mode = 'demo';
        renderDemo();
      });
    }

    if (demoBtn) {
      demoBtn.addEventListener('click', function () {
        state.mode = 'demo';
        renderDemo();
      });
    }

    if (exportBtn) {
      exportBtn.addEventListener('click', function () {
        if (state.mode === 'live' && state.liveData) {
          var rows = [['table_id', 'title', 'tier', 'row', 'intake', 'status', 'rate', 'denom', 'bucket']];
          (state.liveData.tables || []).forEach(function (t) {
            (t.cells || []).forEach(function (c) {
              rows.push([t.table_id, t.title || t.table_id, t.tier || '', c.row_label || c.row, c.col_label || c.col, 'published', fmtRate(c.rate, c.num, c.denom, c.rate_display), c.denom || '', '']);
            });
            (t.withheld || []).forEach(function (h) {
              rows.push([t.table_id, t.title || t.table_id, t.tier || '', h.row_label || h.row, h.col_label || h.col, 'withheld', 'hidden', '', h.bucket || '']);
            });
          });
          exportCsv(rows, 'netherlanded-insights-' + ((state.liveData.meta && state.liveData.meta.institution) || 'live') + '.csv');
          return;
        }
        var dRows = [['institution', 'intake', 'region', 'step', 'phase', 'students', 'completed', 'on_time', 'opened']];
        DEMO_PROTO.step_completion.filter(function (r) {
          return r.institution_id === state.inst && r.intake_month === state.month && r.region === state.region;
        }).forEach(function (r) {
          dRows.push([
            state.inst, r.intake_month, r.region, r.title, PHASES[r.phase] || r.phase, r.students_with_step,
            r.completed_display || (r.completed_pct === null ? 'hidden' : r.completed_pct + '%'),
            r.on_time_display || (r.on_time_pct === null ? '' : r.on_time_pct + '%'),
            r.opened_display || (r.opened_pct === null ? 'hidden' : r.opened_pct + '%')
          ]);
        });
        exportCsv(dRows, 'netherlanded-demo-' + state.inst + '-' + state.month + '.csv');
      });
    }
  }

  function boot() {
    wireEvents();
    loadLive();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
