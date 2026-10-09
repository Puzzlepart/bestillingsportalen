// GovernanceEndDate and GovernanceAnnualReview - the daily parent workflows.
'use strict';
const L = require('./lib');
const { cards } = require('./cards');

const lang = `${L.S('GovernanceLanguage', 'nb-no')}`;
const DRY = L.SB('GovernanceDryRun', 'true');
const CAP = L.SI('GovernanceMaxNotificationsPerRun', '25');
const DAYS_NOTIFY = L.SI('GovernanceNotifyDaysBeforeEndDate', '30');
const DAYS_REMIND = L.SI('GovernanceReminderDays', '14');
const DAYS_DELETE = L.SI('GovernanceDeleteAfterDays', '90');
const DAYS_REVIEW = L.SI('GovernanceAnnualReviewDays', '365');
const DELETION = L.SB('GovernanceEnableDeletion', 'false');

const F = (loop, field) => `items('${loop}')?['${field}']`;
const ITEM_SELECT = 'ID,Title,ObjectGUID,GroupType,OwnersJSON,EndDate,ExcludeFromGovernance,GovernanceStatus,LastNotificationDate,LastAnnualReviewDate,ArchivedDate,GovernanceChatId,GroupCreatedDateTime';

// Conditions shared by every governance filter (item() is a governance list item)
const BASE = [
  "equals(item()?['GroupType'], 'Team')",
  "not(equals(item()?['ExcludeFromGovernance'], true))",
];
const ownersJson = (x) => `json(if(empty(${x}), '[]', ${x}))`;
const HAS_OWNERS = `not(empty(${ownersJson("item()?['OwnersJSON']")}))`;
const passed = (dateExpr) => `lessOrEquals(ticks(${dateExpr}), ticks(utcNow()))`;
const where = (...conds) => `@and(${[...BASE, ...conds].join(', ')})`;

function commonStart() {
  return [
    ['Initialize_variables', L.initVars([
      { name: 'Items', type: 'array', value: [] },
      { name: 'ItemsNextLink', type: 'string', value: '' },
    ])],
    ...L.settingsActions(),
    ['Check_governance_enabled', L.cond(
      `@not(${L.SB('GovernanceEnabled', 'false')})`,
      { Stop_governance_disabled: Object.assign(L.terminate('Succeeded'), { runAfter: {} }) }
    )],
    ['Scope_-_Get_governance_items', L.spGetAllScope(
      'items',
      `${L.listUrl('GovernanceListId')}/items?$select=${ITEM_SELECT}&$top=5000`,
      'Items'
    )],
  ];
}

const wfParams = {
  SiteUrl: "[parameters('requestsSiteUrl')]",
  SettingsListId: "[parameters('requestsSettingsListId')]",
  GovernanceListId: "[parameters('governanceListId')]",
  GovernanceLogListId: "[parameters('governanceLogListId')]",
  ServiceAccountUPN: "[parameters('serviceAccountUPN')]",
};
const extraArmParams = { serviceAccountUPN: { defaultValue: '', type: 'string' } };

const teamsConn = { connection: { name: "@parameters('$connections')['teams']['connectionId']" } };
const postCard = (chatExpr, cardAction) => ({
  type: 'ApiConnection',
  inputs: {
    host: teamsConn,
    method: 'post',
    path: "/v1.0/teams/conversation/adaptivecard/poster/Flow bot/location/@{encodeURIComponent('Group chat')}",
    body: { recipient: `@{${chatExpr}}`, messageBody: `@{string(outputs('${cardAction}'))}` },
  },
});

const logFor = (loop, action, title, details) => L.log(`@{${F(loop, 'ObjectGUID')}}`, `@{${F(loop, 'Title')}}`, action, title, details);
const dryRunLog = (loop, what) => logFor(loop, 'DryRun', `Tørrkjøring: ${what}`,
  `GovernanceDryRun=true - ingenting er sendt eller endret. Ville utført: ${what}. Status: @{${F(loop, 'GovernanceStatus')}}, sluttdato: @{${F(loop, 'EndDate')}}.`);

// ------------------------------------------------------------------ notification loop
// One notification per team: (re)use the governance chat, mark the item as notified
// BEFORE calling GovernanceNotify (which reverts it if the card cannot be posted),
// then hand over to the child workflow.
function notifyLoop({ loop, from, type, newStatus, logAction, logTitle, reuseChat, topic }) {
  const p = loop.replace(/^For_each_/, '');
  const chatId = `outputs('Chat_id_${p}')`;
  const buildMembers = L.select(`@outputs('Owners_${p}')`, {
    '@@odata.type': '#microsoft.graph.aadUserConversationMember',
    roles: ['owner'],
    'user@odata.bind': "https://graph.microsoft.com/v1.0/users('@{item()?['id']}')",
  });
  const createChat = L.graph('POST', 'https://graph.microsoft.com/v1.0/chats', {
    chatType: 'group',
    topic: `@{${L.tExpr(lang, topic[0], topic[1], topic[2])}} - @{${F(loop, 'Title')}}`,
    members: `@union(body('Build_chat_members_${p}'), outputs('Service_account_member'))`,
  });
  const existingChat = `coalesce(${F(loop, 'GovernanceChatId')}, '')`;
  // First notifications get a fresh chat (the owners may have changed since the
  // last one); reminders reuse the chat of the first notification when it exists.
  const chatSteps = reuseChat
    ? [[`Check_new_chat_needed_${p}`, L.cond(`@empty(${existingChat})`, L.seq([[`Build_chat_members_${p}`, buildMembers], [`Create_chat_${p}`, createChat]]))]]
    : [[`Build_chat_members_${p}`, buildMembers], [`Create_chat_${p}`, createChat]];
  const chatStepName = chatSteps[chatSteps.length - 1][0];
  const chatIdExpr = reuseChat
    ? `@if(empty(${existingChat}), actions('Create_chat_${p}')?['outputs']?['body']?['id'], ${existingChat})`
    : `@body('Create_chat_${p}')?['id']`;

  const real = L.seq([
    [`Owners_${p}`, L.compose(`@${ownersJson(F(loop, 'OwnersJSON'))}`)],
    [`Owner_names_${p}`, L.select(`@outputs('Owners_${p}')`, "@coalesce(item()?['displayName'], item()?['upn'])")],
    ...chatSteps,
    [`Chat_id_${p}`, L.compose(chatIdExpr)],
    [`Mark_notified_${p}`, L.spUpdate('GovernanceListId', `@{${F(loop, 'ID')}}`, {
      GovernanceStatus: newStatus,
      LastNotificationDate: '@{utcNow()}',
      GovernanceChatId: `@{${chatId}}`,
    })],
    [`Call_GovernanceNotify_${p}`, {
      type: 'Workflow',
      inputs: {
        host: { triggerName: 'manual', workflow: { id: L.ARM("[resourceId('Microsoft.Logic/workflows', 'GovernanceNotify')]") } },
        body: {
          notificationType: type,
          teamId: `@{${F(loop, 'ObjectGUID')}}`,
          teamName: `@{${F(loop, 'Title')}}`,
          itemId: `@{${F(loop, 'ID')}}`,
          chatId: `@{${chatId}}`,
          endDate: `@{${F(loop, 'EndDate')}}`,
          createdDate: `@{${F(loop, 'GroupCreatedDateTime')}}`,
          ownersDisplayNames: `@{join(body('Owner_names_${p}'), ', ')}`,
          previousStatus: `@{${F(loop, 'GovernanceStatus')}}`,
          previousLastNotificationDate: `@{${F(loop, 'LastNotificationDate')}}`,
          language: `@{${lang}}`,
          guideUrl: `@{${L.S('GovernanceGuideUrl', '')}}`,
          deletionEnabled: `@${DELETION}`,
          deleteAfterDays: `@${DAYS_DELETE}`,
        },
      },
    }],
    [`Log_${p}`, logFor(loop, logAction, logTitle, `Varsel til eierne (@{join(body('Owner_names_${p}'), ', ')}) overlevert til GovernanceNotify for chat @{${chatId}}. Hvis kortet ikke kan postes, logges NotificationFailed og status settes tilbake.`)],
  ]);
  real[`Revert_on_notify_failure_${p}`] = Object.assign(
    L.spUpdate('GovernanceListId', `@{${F(loop, 'ID')}}`, {
      GovernanceStatus: `@{${F(loop, 'GovernanceStatus')}}`,
      LastNotificationDate: `@${F(loop, 'LastNotificationDate')}`,
    }),
    { runAfter: L.after(`Call_GovernanceNotify_${p}`, 'Failed', 'TimedOut') }
  );
  real[`Log_notify_failure_${p}`] = Object.assign(
    logFor(loop, 'NotificationFailed', 'Varsel kunne ikke sendes', `GovernanceNotify kunne ikke startes. Status er satt tilbake, og neste kjøring prøver på nytt. Feil: @{string(actions('Call_GovernanceNotify_${p}')?['outputs']?['body'])}`),
    { runAfter: L.after(`Revert_on_notify_failure_${p}`, 'Succeeded', 'Failed') }
  );
  real[`Log_chat_failure_${p}`] = Object.assign(
    logFor(loop, 'NotificationFailed', 'Chat for varsel kunne ikke opprettes',
      `Opprettelse av gruppechat feilet: @{string(actions('Create_chat_${p}')?['outputs']?['body'])}. Ingenting er endret, og neste kjøring prøver på nytt.`),
    { runAfter: L.after(chatStepName, 'Failed') }
  );

  return L.foreach(`@take(${from}, ${CAP})`, {
    [`Check_dry_run_${p}`]: Object.assign(
      L.cond(`@${DRY}`, { [`Log_dry_run_${p}`]: Object.assign(dryRunLog(loop, `${type} (varsel)`), { runAfter: {} }) }, real),
      { runAfter: {} }
    ),
  });
}

// ------------------------------------------------------------------ archive loop
function archiveLoop({ loop, from, track }) {
  const p = loop.replace(/^For_each_/, '');
  const C = cards(lang, {
    teamName: F(loop, 'Title'), owners: "''", endDate: F(loop, 'EndDate'), createdDate: F(loop, 'GroupCreatedDateTime'),
    guideUrl: L.S('GovernanceGuideUrl', ''), deletionEnabled: DELETION, deleteAfterDays: DAYS_DELETE, responder: "''", newEndDate: "''",
  });
  const reasonText = track === 'enddate'
    ? `${C.T('Teamet **', 'Teamet **', 'The team **')}${C.v(F(loop, 'Title'))}${C.T('** er arkivert (låst for endringer) fordi sluttdatoen er passert.', '** er arkivert (låst for endringar) fordi sluttdatoen er passert.', '** has been archived (locked for changes) because the end date has passed.')}`
    : `${C.T('Teamet **', 'Teamet **', 'The team **')}${C.v(F(loop, 'Title'))}${C.T('** er arkivert (låst for endringer) fordi ingen svarte på den årlige gjennomgangen.', '** er arkivert (låst for endringar) fordi ingen svarte på den årlege gjennomgangen.', '** has been archived (locked for changes) because nobody responded to the annual review.')}`;
  const deletionText = track === 'enddate'
    ? `@{if(${DELETION}, concat(${L.tExpr(lang, 'Teamet slettes permanent etter ', 'Teamet blir sletta permanent etter ', 'The team will be permanently deleted after ')}, string(${DAYS_DELETE}), ${L.tExpr(lang, ' dager (ca. ', ' dagar (ca. ', ' days (approx. ')}, formatDateTime(addDays(utcNow(), ${DAYS_DELETE}), 'dd.MM.yyyy'), ${L.tExpr(lang, '). Kontakt IT hvis teamet ikke skal slettes.', '). Kontakt IT dersom teamet ikkje skal slettast.', '). Contact IT if the team should not be deleted.')}), '')}`
    : '';
  const card = C.card([
    C.header('default', C.T('📁 Teamet er arkivert', '📁 Teamet er arkivert', '📁 Team archived')),
    C.facts([['Team:', C.v(F(loop, 'Title'))], [C.T('Arkivert:', 'Arkivert:', 'Archived:'), "@{formatDateTime(utcNow(), 'dd.MM.yyyy')}"]]),
    C.text(reasonText, { spacing: 'Medium' }),
    C.text(C.T('Eierne kan gjenopprette teamet selv hvis det trengs igjen.', 'Eigarane kan gjenopprette teamet sjølve dersom det trengst igjen.', 'The owners can restore the team themselves if it is needed again.')),
    ...(deletionText ? [C.text(deletionText)] : []),
    C.links,
  ]);
  const title = track === 'enddate' ? 'Team arkivert - sluttdato passert' : 'Team arkivert - ingen svar på årlig gjennomgang';

  const real = L.seq([
    [`Archive_team_${p}`, L.graph('POST', `https://graph.microsoft.com/v1.0/teams/@{${F(loop, 'ObjectGUID')}}/archive`, {})],
    [`Check_archive_result_${p}`, Object.assign(L.cond(
      { or: [
        { equals: [`@outputs('Archive_team_${p}')['statusCode']`, 202] },
        { and: [{ equals: [`@outputs('Archive_team_${p}')['statusCode']`, 400] }, { contains: [`@toLower(string(body('Archive_team_${p}')))`, 'already archived'] }] },
      ] },
      L.seq([
        [`Update_item_archived_${p}`, L.spUpdate('GovernanceListId', `@{${F(loop, 'ID')}}`, { GovernanceStatus: 'Archived', ArchivedDate: '@{utcNow()}', LastNotificationDate: null })],
        [`Log_archived_${p}`, logFor(loop, 'TeamArchived', title, 'Teamet er arkivert automatisk av governance-prosessen.')],
        [`Check_chat_exists_${p}`, L.cond(`@not(empty(coalesce(${F(loop, 'GovernanceChatId')}, '')))`, L.seq([
          [`Card_archived_${p}`, L.compose(card)],
          [`Post_archive_card_${p}`, postCard(F(loop, 'GovernanceChatId'), `Card_archived_${p}`)],
        ]))],
      ]),
      {
        [`Check_team_already_deleted_${p}`]: Object.assign(L.cond(
          { equals: [`@outputs('Archive_team_${p}')['statusCode']`, 404] },
          L.seq([
            [`Update_item_deleted_${p}`, L.spUpdate('GovernanceListId', `@{${F(loop, 'ID')}}`, { GovernanceStatus: 'Deleted' })],
            [`Log_already_deleted_${p}`, logFor(loop, 'TeamAlreadyDeleted', 'Teamet var allerede slettet', 'Teamet skulle arkiveres, men finnes ikke lenger.')],
          ]),
          { [`Log_archive_error_${p}`]: Object.assign(logFor(loop, 'ArchiveError', 'Arkivering feilet', `Status @{outputs('Archive_team_${p}')['statusCode']}: @{string(body('Archive_team_${p}'))}`), { runAfter: {} }) }
        ), { runAfter: {} }),
      }
    ), { runAfter: L.after(`Archive_team_${p}`, 'Succeeded', 'Failed') })],
  ]);
  return L.foreach(`@take(${from}, ${CAP})`, {
    [`Check_dry_run_${p}`]: Object.assign(
      L.cond(`@${DRY}`, { [`Log_dry_run_${p}`]: Object.assign(dryRunLog(loop, 'arkivering'), { runAfter: {} }) }, real),
      { runAfter: {} }
    ),
  });
}

// ------------------------------------------------------------------ delete loop (end-date track only)
function deleteLoop({ loop, from }) {
  const p = loop.replace(/^For_each_/, '');
  const C = cards(lang, {
    teamName: F(loop, 'Title'), owners: "''", endDate: F(loop, 'EndDate'), createdDate: "''",
    guideUrl: L.S('GovernanceGuideUrl', ''), deletionEnabled: DELETION, deleteAfterDays: DAYS_DELETE, responder: "''", newEndDate: "''",
  });
  const card = C.card([
    C.header('attention', C.T('🗑️ Teamet er slettet', '🗑️ Teamet er sletta', '🗑️ Team deleted')),
    C.facts([['Team:', C.v(F(loop, 'Title'))], [C.T('Arkivert siden:', 'Arkivert sidan:', 'Archived since:'), `@{formatDateTime(${F(loop, 'ArchivedDate')}, 'dd.MM.yyyy')}`], [C.T('Slettet:', 'Sletta:', 'Deleted:'), "@{formatDateTime(utcNow(), 'dd.MM.yyyy')}"]]),
    C.text(`${C.T('Teamet **', 'Teamet **', 'The team **')}${C.v(F(loop, 'Title'))}${C.T('** er slettet etter å ha vært arkivert i ', '** er sletta etter å ha vore arkivert i ', '** has been deleted after being archived for ')}@{${DAYS_DELETE}}${C.T(' dager.', ' dagar.', ' days.')}`, { spacing: 'Medium' }),
    C.text(C.T('Mener du dette er en feil, kontakt IT straks. Slettede team kan gjenopprettes av IT i inntil 30 dager.', 'Meiner du dette er ein feil, kontakt IT straks. Sletta team kan gjenopprettast av IT i inntil 30 dagar.', 'If you believe this is a mistake, contact IT immediately. IT can restore deleted teams for up to 30 days.')),
  ]);
  const real = L.seq([
    // Never delete a team the owners have restored since it was archived.
    [`Get_team_status_${p}`, L.graph('GET', `https://graph.microsoft.com/v1.0/teams/@{${F(loop, 'ObjectGUID')}}?$select=id,isArchived`)],
    [`Check_still_archived_${p}`, Object.assign(L.cond(
      `@equals(body('Get_team_status_${p}')?['isArchived'], true)`,
      L.seq([
        [`Delete_group_${p}`, L.graph('DELETE', `https://graph.microsoft.com/v1.0/groups/@{${F(loop, 'ObjectGUID')}}`)],
        [`Check_delete_result_${p}`, Object.assign(L.cond(
          { or: [{ equals: [`@outputs('Delete_group_${p}')['statusCode']`, 204] }, { equals: [`@outputs('Delete_group_${p}')['statusCode']`, 404] }] },
          L.seq([
            [`Update_item_deleted_${p}`, L.spUpdate('GovernanceListId', `@{${F(loop, 'ID')}}`, { GovernanceStatus: 'Deleted' })],
            [`Log_deleted_${p}`, logFor(loop, 'TeamDeleted', 'Team slettet', `Gruppen er slettet ${'@{'}${DAYS_DELETE}} dager etter arkivering. Den kan gjenopprettes fra slettede grupper i Entra ID i inntil 30 dager.`)],
            [`Check_chat_exists_${p}`, L.cond(`@not(empty(coalesce(${F(loop, 'GovernanceChatId')}, '')))`, L.seq([
              [`Card_deleted_${p}`, L.compose(card)],
              [`Post_delete_card_${p}`, postCard(F(loop, 'GovernanceChatId'), `Card_deleted_${p}`)],
            ]))],
          ]),
          { [`Log_delete_error_${p}`]: Object.assign(logFor(loop, 'DeleteError', 'Sletting feilet', `Status @{outputs('Delete_group_${p}')['statusCode']}: @{string(body('Delete_group_${p}'))}`), { runAfter: {} }) }
        ), { runAfter: L.after(`Delete_group_${p}`, 'Succeeded', 'Failed') })],
      ]),
      { [`Update_item_restored_${p}`]: Object.assign(L.spUpdate('GovernanceListId', `@{${F(loop, 'ID')}}`, { GovernanceStatus: 'Active', ArchivedDate: null }), { runAfter: {} }) }
    ), { runAfter: L.after(`Get_team_status_${p}`) })],
  ]);
  return L.foreach(`@take(${from}, ${CAP})`, {
    [`Check_dry_run_${p}`]: Object.assign(
      L.cond(`@${DRY}`, { [`Log_dry_run_${p}`]: Object.assign(dryRunLog(loop, 'sletting'), { runAfter: {} }) }, real),
      { runAfter: {} }
    ),
  });
}

const serviceAccount = ['Service_account_member', L.compose([{
  '@@odata.type': '#microsoft.graph.aadUserConversationMember',
  roles: ['owner'],
  'user@odata.bind': "https://graph.microsoft.com/v1.0/users('@{parameters('ServiceAccountUPN')}')",
}])];

const recurrence = (hour) => ({
  Recurrence: { type: 'Recurrence', recurrence: { frequency: 'Day', interval: 1, schedule: { hours: [String(hour)], minutes: [0] }, timeZone: 'W. Europe Standard Time' } },
});

// ================================================================== GovernanceEndDate
function endDate() {
  const items = "@variables('Items')";
  const HAS_END = "not(empty(item()?['EndDate']))";
  const actions = L.seq([
    ...commonStart(),
    serviceAccount,
    ['Filter_first_notification', L.query(items, where(HAS_END, "equals(item()?['GovernanceStatus'], 'Active')", HAS_OWNERS,
      passed(`addDays(item()?['EndDate'], mul(-1, ${DAYS_NOTIFY}))`)))],
    ['Filter_reminder', L.query(items, where(HAS_END, "equals(item()?['GovernanceStatus'], 'EndDateNotified')", "not(empty(item()?['LastNotificationDate']))", HAS_OWNERS,
      passed(`addDays(item()?['LastNotificationDate'], ${DAYS_REMIND})`)))],
    // Archive once the end date has passed - an unanswered reminder also gets its full
    // reminder period first, even when the end date was set close to today.
    ['Filter_archive', L.query(items, where(HAS_END, passed("item()?['EndDate']"),
      `or(equals(item()?['GovernanceStatus'], 'EndDateConfirmed'), and(equals(item()?['GovernanceStatus'], 'EndDateReminded'), not(empty(item()?['LastNotificationDate'])), ${passed(`addDays(item()?['LastNotificationDate'], ${DAYS_REMIND})`)}))`))],
    ['Filter_delete', L.query(items, where(DELETION, HAS_END, "equals(item()?['GovernanceStatus'], 'Archived')", "not(empty(item()?['ArchivedDate']))",
      passed(`addDays(item()?['ArchivedDate'], ${DAYS_DELETE})`)))],
    ['For_each_first_notification', notifyLoop({
      loop: 'For_each_first_notification', from: "body('Filter_first_notification')", type: 'enddate-first', newStatus: 'EndDateNotified',
      logAction: 'EndDateNotification', logTitle: 'Varsel om sluttdato sendt', reuseChat: false, topic: ['Sluttdato', 'Sluttdato', 'End date'],
    })],
    ['For_each_reminder', notifyLoop({
      loop: 'For_each_reminder', from: "body('Filter_reminder')", type: 'enddate-reminder', newStatus: 'EndDateReminded',
      logAction: 'EndDateReminder', logTitle: 'Påminnelse om sluttdato sendt', reuseChat: true, topic: ['Sluttdato', 'Sluttdato', 'End date'],
    })],
    ['For_each_archive', archiveLoop({ loop: 'For_each_archive', from: "body('Filter_archive')", track: 'enddate' })],
    ['For_each_delete', deleteLoop({ loop: 'For_each_delete', from: "body('Filter_delete')" })],
  ]);
  // A failing team must not stop the rest of the run.
  for (const k of ['For_each_reminder', 'For_each_archive', 'For_each_delete']) {
    const keys = Object.keys(actions);
    actions[k].runAfter = { [keys[keys.indexOf(k) - 1]]: ['Succeeded', 'Failed', 'TimedOut'] };
  }
  return L.template({
    name: 'GovernanceEndDate',
    description: 'Teams governance - end-date notifications, reminders, archiving and (optional) deletion',
    extraArmParams, wfParams, connections: { ...L.TEAMS_CONNECTION },
    triggers: recurrence(8), actions,
  });
}

// ================================================================== GovernanceAnnualReview
function annualReview() {
  const items = "@variables('Items')";
  const NO_END = "empty(item()?['EndDate'])";
  const ownerless = L.seq([
    ['Select_ownerless_names', L.select("@body('Filter_ownerless')", "@{item()?['Title']}")],
    ['Send_ownerless_email', {
      type: 'ApiConnection',
      inputs: {
        host: { connection: { name: "@parameters('$connections')['office365']['connectionId']" } },
        method: 'post',
        path: '/v2/Mail',
        body: {
          To: `@{${L.S('GovernanceITEmail', '')}}`,
          Subject: "Teams governance - @{length(body('Filter_ownerless'))} team uten eiere",
          Body: "<p>Følgende <strong>@{length(body('Filter_ownerless'))}</strong> team har ingen eiere og må følges opp manuelt. De får verken varsler eller årlig gjennomgang før de har fått en eier.</p><ul><li>@{join(body('Select_ownerless_names'), '</li><li>')}</li></ul><p><a href=\"@{parameters('SiteUrl')}/Lists/TeamsGovernance/NoOwners.aspx\">Vis team uten eiere</a></p>",
          Importance: 'Normal',
        },
      },
    }],
    ['Log_ownerless_email', L.log('', 'Team uten eiere', 'OwnerlessReport', 'Rapport om team uten eiere sendt', `@{length(body('Filter_ownerless'))} team uten eiere rapportert til @{${L.S('GovernanceITEmail', '')}}.`)],
  ]);

  const actions = L.seq([
    ...commonStart(),
    serviceAccount,
    ['Filter_annual_review', L.query(items, where(NO_END, "equals(item()?['GovernanceStatus'], 'Active')", HAS_OWNERS,
      `if(empty(item()?['LastAnnualReviewDate']), and(not(empty(item()?['GroupCreatedDateTime'])), ${passed(`addDays(coalesce(item()?['GroupCreatedDateTime'], utcNow()), ${DAYS_REVIEW})`)}), ${passed(`addDays(coalesce(item()?['LastAnnualReviewDate'], utcNow()), ${DAYS_REVIEW})`)})`))],
    ['Filter_review_reminder', L.query(items, where(NO_END, "equals(item()?['GovernanceStatus'], 'AnnualReviewNotified')", "not(empty(item()?['LastNotificationDate']))", HAS_OWNERS,
      passed(`addDays(item()?['LastNotificationDate'], ${DAYS_REMIND})`)))],
    ['Filter_escalate', L.query(items, where(NO_END, "equals(item()?['GovernanceStatus'], 'AnnualReviewReminded')", "not(empty(item()?['LastNotificationDate']))",
      passed(`addDays(item()?['LastNotificationDate'], ${DAYS_REMIND})`)))],
    ['Filter_ownerless', L.query(items, `@and(not(equals(item()?['ExcludeFromGovernance'], true)), not(equals(item()?['GovernanceStatus'], 'Deleted')), not(equals(item()?['GovernanceStatus'], 'Archived')), not(${HAS_OWNERS}))`)],
    ['For_each_annual_review', notifyLoop({
      loop: 'For_each_annual_review', from: "body('Filter_annual_review')", type: 'annual-review', newStatus: 'AnnualReviewNotified',
      logAction: 'AnnualReviewNotification', logTitle: 'Årlig gjennomgang sendt', reuseChat: false, topic: ['Årlig gjennomgang', 'Årleg gjennomgang', 'Annual review'],
    })],
    ['For_each_review_reminder', notifyLoop({
      loop: 'For_each_review_reminder', from: "body('Filter_review_reminder')", type: 'annual-review-reminder', newStatus: 'AnnualReviewReminded',
      logAction: 'AnnualReviewReminder', logTitle: 'Påminnelse om årlig gjennomgang sendt', reuseChat: true, topic: ['Årlig gjennomgang', 'Årleg gjennomgang', 'Annual review'],
    })],
    ['For_each_escalate', archiveLoop({ loop: 'For_each_escalate', from: "body('Filter_escalate')", track: 'annual' })],
    // Weekly (Mondays) so IT is not mailed the same list every day.
    ['Check_ownerless_report', L.cond(
      `@and(not(empty(${L.S('GovernanceITEmail', '')})), equals(dayOfWeek(convertFromUtc(utcNow(), 'W. Europe Standard Time')), 1), greater(length(body('Filter_ownerless')), 0))`,
      ownerless
    )],
  ]);
  for (const k of ['For_each_review_reminder', 'For_each_escalate', 'Check_ownerless_report']) {
    const keys = Object.keys(actions);
    actions[k].runAfter = { [keys[keys.indexOf(k) - 1]]: ['Succeeded', 'Failed', 'TimedOut'] };
  }
  return L.template({
    name: 'GovernanceAnnualReview',
    description: 'Teams governance - annual review of teams without an end date, and weekly report of teams without owners',
    extraArmParams, wfParams, connections: { ...L.TEAMS_CONNECTION, ...L.O365_CONNECTION },
    triggers: recurrence(9), actions,
  });
}

module.exports = { endDate, annualReview };
