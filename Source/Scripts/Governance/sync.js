// GovernanceSync - daily sync of Microsoft 365 groups/Teams into the Teams Governance list.
'use strict';
const L = require('./lib');

const GROUPS_URL = "https://graph.microsoft.com/v1.0/groups?$filter=groupTypes/any(c:c+eq+'Unified')&$select=id,displayName,createdDateTime,resourceProvisioningOptions,visibility,description&$expand=owners($select=id,userPrincipalName,displayName)&$top=999";
const USE_EXPIRATION = L.SB('EnableExpirationDate', 'false');
const PORTAL_SCOPE = `equals(toLower(${L.S('GovernanceScope', 'All')}), 'portal')`;

const groupType = (g) => `@if(contains(coalesce(${g}?['resourceProvisioningOptions'], json('[]')), 'Team'), 'Team', 'M365Group')`;
const ownersSteps = (p, g) => [
  // Only users - a service principal can own a group, but cannot be added to a chat.
  [`Filter_user_owners_${p}`, L.query(`@coalesce(${g}?['owners'], json('[]'))`, "@equals(item()?['@odata.type'], '#microsoft.graph.user')")],
  [`Select_owners_${p}`, L.select(`@body('Filter_user_owners_${p}')`, { upn: "@item()?['userPrincipalName']", displayName: "@item()?['displayName']", id: "@item()?['id']" })],
];

function sync() {
  const graphPages = L.scope(L.seq([
    ['Get_groups_page', L.graph('GET', GROUPS_URL)],
    ['Set_Groups', L.setVar('Groups', "@body('Get_groups_page')?['value']")],
    ['Set_GroupsNextLink', L.setVar('GroupsNextLink', "@{coalesce(body('Get_groups_page')?['@odata.nextLink'], '')}")],
    ['Until_all_groups_pages', {
      type: 'Until',
      expression: "@equals(variables('GroupsNextLink'), '')",
      limit: { count: 500, timeout: 'PT2H' },
      actions: L.seq([
        ['Get_next_groups_page', L.graph('GET', "@{variables('GroupsNextLink')}")],
        ['Union_groups', L.compose("@union(variables('Groups'), body('Get_next_groups_page')?['value'])")],
        ['Update_Groups', L.setVar('Groups', "@outputs('Union_groups')")],
        ['Update_GroupsNextLink', L.setVar('GroupsNextLink', "@{coalesce(body('Get_next_groups_page')?['@odata.nextLink'], '')}")],
      ]),
    }],
  ]));

  const newGroup = "items('For_each_new_group')";
  const exGroup = "items('For_each_existing_group')";
  const spItem = "body('Find_item_to_update')[0]";

  const archiveBatch = L.foreach("@chunk(body('Select_team_ids'), 20)", L.seq([
    ['Build_batch_requests', L.select("@items('For_each_batch')", { id: '@{item()}', method: 'GET', url: "/teams/@{item()}?$select=id,isArchived" })],
    ['Send_batch_request', L.graph('POST', 'https://graph.microsoft.com/v1.0/$batch', { requests: "@body('Build_batch_requests')" })],
    // Only answers we actually got count - a throttled request must not read as "not archived".
    ['Filter_answered', L.query("@coalesce(body('Send_batch_request')?['responses'], json('[]'))", "@equals(item()?['status'], 200)")],
    ['Select_answered_ids', L.select("@body('Filter_answered')", "@item()?['id']")],
    ['Filter_archived_in_batch', L.query("@body('Filter_answered')", "@equals(item()?['body']?['isArchived'], true)")],
    ['Select_archived_ids', L.select("@body('Filter_archived_in_batch')", "@item()?['id']")],
    ['Union_checked', L.compose("@union(variables('CheckedTeamIds'), body('Select_answered_ids'))")],
    ['Update_CheckedTeamIds', L.setVar('CheckedTeamIds', "@outputs('Union_checked')")],
    ['Union_archived', L.compose("@union(variables('ArchivedTeamIds'), body('Select_archived_ids'))")],
    ['Update_ArchivedTeamIds', L.setVar('ArchivedTeamIds', "@outputs('Union_archived')")],
  ]), 1);

  const actions = L.seq([
    ['Initialize_variables', L.initVars([
      { name: 'Groups', type: 'array', value: [] },
      { name: 'GroupsNextLink', type: 'string', value: '' },
      { name: 'Items', type: 'array', value: [] },
      { name: 'ItemsNextLink', type: 'string', value: '' },
      { name: 'Requests', type: 'array', value: [] },
      { name: 'RequestsNextLink', type: 'string', value: '' },
      { name: 'ArchivedTeamIds', type: 'array', value: [] },
      { name: 'CheckedTeamIds', type: 'array', value: [] },
    ])],
    ...L.settingsActions(),
    ['Scope_-_Get_all_groups', graphPages],
    ['Scope_-_Get_governance_items', L.spGetAllScope('items',
      `${L.listUrl('GovernanceListId')}/items?$select=ID,Title,ObjectGUID,GroupType,OwnersJSON,Visibility,GroupDescription,GovernanceStatus&$top=5000`, 'Items')],
    ['Scope_-_Get_requests', L.spGetAllScope('requests',
      `${L.listUrl('RequestsListId')}/items?$select=GroupId,ExpirationDate&$top=5000`, 'Requests')],
    ['Filter_requests_with_group', L.query("@variables('Requests')", "@not(empty(item()?['GroupId']))")],
    ['Select_request_group_ids', L.select("@body('Filter_requests_with_group')", "@item()?['GroupId']")],
    // GovernanceScope=Portal limits governance to groups ordered through Bestillingsportalen
    ['Filter_groups_in_scope', L.query("@variables('Groups')", `@or(not(${PORTAL_SCOPE}), contains(body('Select_request_group_ids'), item()?['id']))`)],
    ['Filter_teams_in_scope', L.query("@body('Filter_groups_in_scope')", "@contains(coalesce(item()?['resourceProvisioningOptions'], json('[]')), 'Team')")],
    ['Select_team_ids', L.select("@body('Filter_teams_in_scope')", "@item()?['id']")],
    ['For_each_batch', archiveBatch],
    ['Select_all_group_ids', L.select("@variables('Groups')", "@item()?['id']")],
    ['Select_item_guids', L.select("@variables('Items')", "@item()?['ObjectGUID']")],
    ['Filter_new_groups', L.query("@body('Filter_groups_in_scope')", "@not(contains(body('Select_item_guids'), item()?['id']))")],
    ['Filter_existing_groups', L.query("@body('Filter_groups_in_scope')", "@contains(body('Select_item_guids'), item()?['id'])")],
    ['For_each_new_group', L.foreach("@body('Filter_new_groups')", L.seq([
      ...ownersSteps('new', newGroup),
      ['Lookup_request', L.query("@body('Filter_requests_with_group')", `@equals(item()?['GroupId'], ${newGroup}?['id'])`)],
      ['Create_item', L.spCreate('GovernanceListId', {
        Title: `@{${newGroup}?['displayName']}`,
        ObjectGUID: `@{${newGroup}?['id']}`,
        GroupType: groupType(newGroup),
        OwnersJSON: "@{string(body('Select_owners_new'))}",
        Visibility: `@{coalesce(${newGroup}?['visibility'], 'Private')}`,
        GroupCreatedDateTime: `@{${newGroup}?['createdDateTime']}`,
        GroupDescription: `@{coalesce(${newGroup}?['description'], '')}`,
        // Only a date the orderer chose - see EnableExpirationDate / Teams-governance.md
        EndDate: `@if(and(${USE_EXPIRATION}, greater(length(body('Lookup_request')), 0), not(empty(first(body('Lookup_request'))?['ExpirationDate']))), first(body('Lookup_request'))?['ExpirationDate'], null)`,
        ExcludeFromGovernance: false,
        GovernanceStatus: `@{if(contains(variables('ArchivedTeamIds'), ${newGroup}?['id']), 'Archived', 'Active')}`,
        ArchivedDate: `@if(contains(variables('ArchivedTeamIds'), ${newGroup}?['id']), utcNow(), null)`,
      })],
    ]), 10)],
    ['For_each_existing_group', L.foreach("@body('Filter_existing_groups')", L.seq([
      ['Find_item_to_update', L.query("@variables('Items')", `@equals(item()?['ObjectGUID'], ${exGroup}?['id'])`)],
      ...ownersSteps('existing', exGroup),
      // Update only when something changed, so the list does not get a new version every night.
      ['Check_changes', L.cond({ or: [
        { not: { equals: [`@${exGroup}?['displayName']`, `@${spItem}?['Title']`] } },
        { not: { equals: [groupType(exGroup), `@${spItem}?['GroupType']`] } },
        { not: { equals: ["@string(body('Select_owners_existing'))", `@coalesce(${spItem}?['OwnersJSON'], '')`] } },
        { not: { equals: [`@coalesce(${exGroup}?['visibility'], 'Private')`, `@${spItem}?['Visibility']`] } },
        { not: { equals: [`@coalesce(${exGroup}?['description'], '')`, `@coalesce(${spItem}?['GroupDescription'], '')`] } },
        { equals: [`@${spItem}?['GovernanceStatus']`, 'Deleted'] },
      ] }, {
        Update_item: Object.assign(L.spUpdate('GovernanceListId', `@{${spItem}?['ID']}`, {
          Title: `@{${exGroup}?['displayName']}`,
          GroupType: groupType(exGroup),
          OwnersJSON: "@{string(body('Select_owners_existing'))}",
          Visibility: `@{coalesce(${exGroup}?['visibility'], 'Private')}`,
          GroupDescription: `@{coalesce(${exGroup}?['description'], '')}`,
          // A group that reappears (restored from the recycle bin) is active again
          GovernanceStatus: `@{if(equals(${spItem}?['GovernanceStatus'], 'Deleted'), 'Active', ${spItem}?['GovernanceStatus'])}`,
        }), { runAfter: {} }),
      })],
    ]), 10)],
    // Deleted detection uses ALL groups (not the scoped set), so narrowing the scope
    // never marks existing items as deleted. An empty Graph result is treated as an error.
    ['Filter_deleted_groups', L.query("@variables('Items')", "@and(greater(length(variables('Groups')), 0), not(contains(body('Select_all_group_ids'), item()?['ObjectGUID'])), not(equals(item()?['GovernanceStatus'], 'Deleted')))")],
    ['For_each_deleted_group', L.foreach("@body('Filter_deleted_groups')", L.seq([
      ['Mark_deleted', L.spUpdate('GovernanceListId', "@{items('For_each_deleted_group')?['ID']}", { GovernanceStatus: 'Deleted' })],
      ['Log_deleted', L.log("@{items('For_each_deleted_group')?['ObjectGUID']}", "@{items('For_each_deleted_group')?['Title']}", 'TeamDeleted', 'Gruppen finnes ikke lenger', 'Gruppen ble ikke funnet i Microsoft Graph ved synkronisering og er markert som slettet.')],
    ]), 10)],
    ['Filter_externally_archived', L.query("@variables('Items')", "@and(contains(variables('ArchivedTeamIds'), item()?['ObjectGUID']), not(equals(item()?['GovernanceStatus'], 'Archived')), not(equals(item()?['GovernanceStatus'], 'Deleted')))")],
    ['For_each_externally_archived', L.foreach("@body('Filter_externally_archived')", L.seq([
      ['Mark_archived', L.spUpdate('GovernanceListId', "@{items('For_each_externally_archived')?['ID']}", { GovernanceStatus: 'Archived', ArchivedDate: '@{utcNow()}', LastNotificationDate: null })],
      ['Log_externally_archived', L.log("@{items('For_each_externally_archived')?['ObjectGUID']}", "@{items('For_each_externally_archived')?['Title']}", 'ExternalArchiveDetected', 'Team arkivert utenfor governance', 'Teamet er arkivert av en eier eller administrator. Statusen er oppdatert.')],
    ]), 10)],
    // Restored = archived in the list, but Graph answered that the team is no longer archived.
    ['Filter_restored', L.query("@variables('Items')", "@and(equals(item()?['GovernanceStatus'], 'Archived'), contains(variables('CheckedTeamIds'), item()?['ObjectGUID']), not(contains(variables('ArchivedTeamIds'), item()?['ObjectGUID'])))")],
    ['For_each_restored', L.foreach("@body('Filter_restored')", L.seq([
      // Restoring counts as confirming the team is in use - the next annual review is a year out.
      ['Mark_restored', L.spUpdate('GovernanceListId', "@{items('For_each_restored')?['ID']}", { GovernanceStatus: 'Active', ArchivedDate: null, LastNotificationDate: null, LastAnnualReviewDate: '@{utcNow()}' })],
      ['Log_restored', L.log("@{items('For_each_restored')?['ObjectGUID']}", "@{items('For_each_restored')?['Title']}", 'TeamRestored', 'Team gjenopprettet fra arkiv', 'Teamet er ikke lenger arkivert i Teams. Statusen er satt til Active.')],
    ]), 10)],
    ['Log_sync_completed', L.log('', 'GovernanceSync', 'SyncCompleted', 'Synkronisering fullført',
      "Grupper i Graph: @{length(variables('Groups'))}. I omfang: @{length(body('Filter_groups_in_scope'))}. Nye: @{length(body('Filter_new_groups'))}. Kontrollert: @{length(body('Filter_existing_groups'))}. Markert slettet: @{length(body('Filter_deleted_groups'))}. Arkivert utenfor governance: @{length(body('Filter_externally_archived'))}. Gjenopprettet: @{length(body('Filter_restored'))}. Omfang: @{" + L.S('GovernanceScope', 'All') + '}.')],
  ]);
  // Let the later steps run even if one team failed in a loop.
  for (const k of ['Filter_deleted_groups', 'Filter_externally_archived', 'Filter_restored', 'Log_sync_completed']) {
    const keys = Object.keys(actions);
    actions[k].runAfter = { [keys[keys.indexOf(k) - 1]]: ['Succeeded', 'Failed'] };
  }

  return L.template({
    name: 'GovernanceSync',
    description: 'Teams governance - daily sync of Microsoft 365 groups and Teams to the Teams Governance list',
    extraArmParams: { requestsListId: { defaultValue: '', type: 'string' } },
    wfParams: {
      SiteUrl: "[parameters('requestsSiteUrl')]",
      SettingsListId: "[parameters('requestsSettingsListId')]",
      GovernanceListId: "[parameters('governanceListId')]",
      GovernanceLogListId: "[parameters('governanceLogListId')]",
      RequestsListId: "[parameters('requestsListId')]",
    },
    triggers: { Recurrence: { type: 'Recurrence', recurrence: { frequency: 'Day', interval: 1, schedule: { hours: ['3'], minutes: [0] }, timeZone: 'W. Europe Standard Time' } } },
    actions,
  });
}

module.exports = { sync };
