// GovernanceNotify - child workflow. Posts one governance card to the team's
// governance chat, waits for an owner's response and processes it.
'use strict';
const L = require('./lib');
const { cards } = require('./cards');

const TB = (k) => `triggerBody()?['${k}']`;
const lang = "variables('Lang')";
const ctx = {
  teamName: TB('teamName'),
  owners: TB('ownersDisplayNames'),
  endDate: TB('endDate'),
  createdDate: TB('createdDate'),
  guideUrl: `coalesce(${TB('guideUrl')}, '')`,
  deletionEnabled: `equals(${TB('deletionEnabled')}, true)`,
  deleteAfterDays: `coalesce(${TB('deleteAfterDays')}, 90)`,
  responder: "outputs('Get_responder')",
  newEndDate: "outputs('Get_response_data')?['newEndDate']",
};
const C = cards(lang, ctx);

const teamsConn = { connection: { name: "@parameters('$connections')['teams']['connectionId']" } };
const FLOWBOT = "Flow bot/location/@{encodeURIComponent('Group chat')}";
const updateCard = (cardAction) => ({
  type: 'ApiConnection',
  inputs: {
    host: teamsConn,
    method: 'post',
    path: `/v1.0/teams/conversation/updateAdaptivecard/poster/${FLOWBOT}`,
    body: { messageId: "@{outputs('Get_message_id')}", recipient: `@{${TB('chatId')}}`, messageBody: `@{string(outputs('${cardAction}'))}` },
  },
});
const postCard = (cardAction) => ({
  type: 'ApiConnection',
  inputs: {
    host: teamsConn,
    method: 'post',
    path: `/v1.0/teams/conversation/adaptivecard/poster/${FLOWBOT}`,
    body: { recipient: `@{${TB('chatId')}}`, messageBody: `@{string(outputs('${cardAction}'))}` },
  },
});

const item = `@{${TB('itemId')}}`;
const teamId = `@{${TB('teamId')}}`;
const teamName = `@{${TB('teamName')}}`;
const who = "@{coalesce(outputs('Get_responder_upn'), 'System')}";
const logAs = (action, title, details) => L.log(teamId, teamName, action, title, details, who);
const logSys = (action, title, details) => L.log(teamId, teamName, action, title, details);

const cases = {
  Case_extend: {
    case: 'extend',
    actions: L.seq([
      ['Update_item_extended', L.spUpdate('GovernanceListId', item, {
        EndDate: "@{outputs('Get_response_data')?['newEndDate']}",
        GovernanceStatus: 'Active',
        LastNotificationDate: null,
        LastMessageId: "@{outputs('Get_message_id')}",
      })],
      ['Card_extended', L.compose(C.resolved.extended)],
      ['Update_card_extended', updateCard('Card_extended')],
      ['Log_extended', logAs('EndDateExtended', 'Sluttdato forlenget',
        `Sluttdato forlenget fra @{formatDateTime(${TB('endDate')}, 'dd.MM.yyyy')} til @{formatDateTime(outputs('Get_response_data')?['newEndDate'], 'dd.MM.yyyy')} av @{outputs('Get_responder')}.`)],
    ]),
  },
  Case_no_extension: {
    case: 'no-extension',
    actions: L.seq([
      ['Update_item_confirmed', L.spUpdate('GovernanceListId', item, { GovernanceStatus: 'EndDateConfirmed', LastMessageId: "@{outputs('Get_message_id')}" })],
      ['Card_no_extension', L.compose(C.resolved.noExtension)],
      ['Update_card_no_extension', updateCard('Card_no_extension')],
      ['Log_confirmed', logAs('EndDateConfirmed', 'Avslutning bekreftet', "@{outputs('Get_responder')} bekreftet at teamet skal avsluttes på sluttdatoen.")],
    ]),
  },
  Case_still_needed: {
    case: 'still-needed',
    actions: L.seq([
      ['Update_item_still_needed', L.spUpdate('GovernanceListId', item, {
        GovernanceStatus: 'Active',
        LastAnnualReviewDate: '@{utcNow()}',
        LastNotificationDate: null,
        LastMessageId: "@{outputs('Get_message_id')}",
      })],
      ['Card_still_needed', L.compose(C.resolved.stillNeeded)],
      ['Update_card_still_needed', updateCard('Card_still_needed')],
      ['Log_still_needed', logAs('UsageConfirmed', 'Årlig gjennomgang fullført', "@{outputs('Get_responder')} bekreftet at teamet fortsatt er i bruk.")],
    ]),
  },
  Case_not_needed: {
    case: 'not-needed',
    actions: L.seq([
      ['Archive_team', L.graph('POST', `https://graph.microsoft.com/v1.0/teams/${teamId}/archive`, {})],
      ['Check_archive_result', Object.assign(
        L.cond(
          { or: [
            { equals: ["@outputs('Archive_team')['statusCode']", 202] },
            { and: [{ equals: ["@outputs('Archive_team')['statusCode']", 400] }, { contains: ["@toLower(string(body('Archive_team')))", 'already archived'] }] },
          ] },
          L.seq([
            ['Update_item_archived', L.spUpdate('GovernanceListId', item, { GovernanceStatus: 'Archived', ArchivedDate: '@{utcNow()}', LastNotificationDate: null, LastMessageId: "@{outputs('Get_message_id')}" })],
            ['Card_archived', L.compose(C.resolved.archived)],
            ['Update_card_archived', updateCard('Card_archived')],
            ['Log_archived', logAs('TeamArchived', 'Team arkivert etter svar på årlig gjennomgang', "@{outputs('Get_responder')} svarte at teamet ikke lenger trengs. Teamet er arkivert.")],
          ]),
          {
            Check_team_already_deleted: L.cond(
              { equals: ["@outputs('Archive_team')['statusCode']", 404] },
              L.seq([
                ['Update_item_deleted', L.spUpdate('GovernanceListId', item, { GovernanceStatus: 'Deleted', LastNotificationDate: null })],
                ['Card_already_gone', L.compose(C.resolved.alreadyGone)],
                ['Update_card_already_gone', updateCard('Card_already_gone')],
                ['Log_already_deleted', logAs('TeamAlreadyDeleted', 'Teamet var allerede slettet', 'Svar om avslutning kom inn, men teamet finnes ikke lenger.')],
              ]),
              {
                Log_archive_error: Object.assign(
                  logAs('ArchiveError', 'Arkivering feilet', "Arkivering etter svar feilet med status @{outputs('Archive_team')['statusCode']}: @{string(body('Archive_team'))}"),
                  { runAfter: {} }
                ),
              }
            ),
          }
        ),
        { runAfter: L.after('Archive_team', 'Succeeded', 'Failed') }
      )],
    ]),
  },
};

const typeCase = (id, type, cardObj) => [id, { case: type, actions: { [`Set_card_${id}`]: Object.assign(L.setVar('CardBody', cardObj), { runAfter: {} }) } }];

const actions = L.seq([
  ['Initialize_variables', L.initVars([
    { name: 'Lang', type: 'string', value: `@{coalesce(${TB('language')}, 'nb-no')}` },
    { name: 'CardBody', type: 'object', value: {} },
  ])],
  ['Response', { type: 'Response', kind: 'Http', inputs: { statusCode: 200, body: { accepted: true } } }],
  ['Switch_on_notification_type', {
    type: 'Switch',
    expression: `@${TB('notificationType')}`,
    cases: Object.fromEntries([
      typeCase('enddate_first', 'enddate-first', C.enddateFirst),
      typeCase('enddate_reminder', 'enddate-reminder', C.enddateReminder),
      typeCase('annual_review', 'annual-review', C.annualReview),
      typeCase('annual_review_reminder', 'annual-review-reminder', C.annualReviewReminder),
    ]),
    default: { actions: { Terminate_unknown_type: Object.assign(L.terminate('Failed'), { inputs: { runStatus: 'Failed', runError: { code: 'UnknownNotificationType', message: `@{${TB('notificationType')}}` } }, runAfter: {} }) } },
  }],
  ['Post_adaptive_card_and_wait_for_a_response', {
    type: 'ApiConnectionWebhook',
    inputs: {
      host: teamsConn,
      path: `/v1.0/teams/conversation/gatherinput/poster/${FLOWBOT}/$subscriptions`,
      body: {
        notificationUrl: '@{listCallbackUrl()}',
        body: {
          messageBody: "@{string(variables('CardBody'))}",
          updateMessage: `@{${require('./lib').tExpr(lang, 'Takk for svaret!', 'Takk for svaret!', 'Thank you for your response!')}}`,
          recipient: { recipient: `@{${TB('chatId')}}` },
        },
      },
    },
    // The card expires after 14 days - the same as the default reminder interval.
    limit: { timeout: 'P14D' },
  }],
]);

actions['Scope_-_Handle_response'] = {
  type: 'Scope',
  runAfter: L.after('Post_adaptive_card_and_wait_for_a_response'),
  actions: L.seq([
    ['Get_response_data', L.compose("@body('Post_adaptive_card_and_wait_for_a_response')?['data']")],
    ['Get_responder', L.compose("@coalesce(body('Post_adaptive_card_and_wait_for_a_response')?['responder']?['displayName'], body('Post_adaptive_card_and_wait_for_a_response')?['responder']?['userPrincipalName'], 'Ukjent')")],
    ['Get_responder_upn', L.compose("@body('Post_adaptive_card_and_wait_for_a_response')?['responder']?['userPrincipalName']")],
    ['Get_message_id', L.compose("@body('Post_adaptive_card_and_wait_for_a_response')?['messageId']")],
    ['Switch_on_action_id', { type: 'Switch', expression: "@outputs('Get_response_data')?['actionId']", cases }],
  ]),
};

actions['Scope_-_Handle_timeout'] = {
  type: 'Scope',
  runAfter: L.after('Post_adaptive_card_and_wait_for_a_response', 'TimedOut'),
  actions: L.seq([
    ['Card_expired', L.compose(C.expired)],
    ['Post_expired_card', postCard('Card_expired')],
    ['Log_expired', Object.assign(logSys('NotificationExpired', 'Varsel utløpt uten svar', `Ingen svar på varselet (@{${TB('notificationType')}}) innen fristen.`), { runAfter: L.after('Post_expired_card', 'Succeeded', 'Failed') })],
  ]),
};

// The card could not be posted (chat gone, connection not authorised, ...). The
// parent already set the notified status - put the previous status back so the
// next run retries, and make the failure visible in the log.
actions['Scope_-_Handle_post_failure'] = {
  type: 'Scope',
  runAfter: L.after('Post_adaptive_card_and_wait_for_a_response', 'Failed'),
  actions: L.seq([
    ['Revert_item_status', L.spUpdate('GovernanceListId', item, {
      GovernanceStatus: `@{coalesce(${TB('previousStatus')}, 'Active')}`,
      LastNotificationDate: `@if(empty(${TB('previousLastNotificationDate')}), null, ${TB('previousLastNotificationDate')})`,
    })],
    ['Log_post_failure', Object.assign(logSys('NotificationFailed', 'Varsel kunne ikke sendes',
      `Kortet (@{${TB('notificationType')}}) kunne ikke postes i chatten @{${TB('chatId')}}. Status er satt tilbake til @{coalesce(${TB('previousStatus')}, 'Active')}, og neste kjøring prøver på nytt. Feil: @{string(actions('Post_adaptive_card_and_wait_for_a_response')?['outputs']?['body'])}`),
      { runAfter: L.after('Revert_item_status', 'Succeeded', 'Failed') })],
  ]),
};

actions['Log_response_failure'] = Object.assign(
  logSys('ResponseError', 'Behandling av svar feilet', "Svaret ble mottatt, men ikke behandlet ferdig. Se kjøringshistorikken til GovernanceNotify. Svar: @{string(body('Post_adaptive_card_and_wait_for_a_response')?['data'])}"),
  { runAfter: L.after('Scope_-_Handle_response', 'Failed', 'TimedOut') }
);

const tpl = L.template({
  name: 'GovernanceNotify',
  description: 'Teams governance - posts one governance card and processes the response',
  wfParams: {
    SiteUrl: "[parameters('requestsSiteUrl')]",
    GovernanceListId: "[parameters('governanceListId')]",
    GovernanceLogListId: "[parameters('governanceLogListId')]",
  },
  connections: { ...L.TEAMS_CONNECTION },
  triggers: {
    manual: {
      type: 'Request',
      kind: 'Http',
      inputs: {
        method: 'POST',
        schema: {
          type: 'object',
          properties: Object.fromEntries(
            ['notificationType', 'teamId', 'teamName', 'itemId', 'chatId', 'endDate', 'createdDate', 'ownersDisplayNames', 'previousStatus', 'previousLastNotificationDate', 'language', 'guideUrl']
              .map((k) => [k, { type: 'string' }])
              .concat([['deletionEnabled', { type: 'boolean' }], ['deleteAfterDays', { type: 'integer' }]])
          ),
          required: ['notificationType', 'teamId', 'itemId', 'chatId'],
        },
      },
    },
  },
  actions,
});
// Settings list is not read here - the parent passes everything in.
delete tpl.parameters.requestsSettingsListId;
module.exports = tpl;
