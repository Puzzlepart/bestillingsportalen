// Shared helpers for generating the Teams governance Logic App ARM templates.
'use strict';

// ---------------------------------------------------------------- ARM wrapper
const ARM_PARAMS = {
  resourceGroupName: { defaultValue: '', type: 'string' },
  subscriptionId: { defaultValue: '', type: 'string' },
  location: { defaultValue: '', type: 'string' },
  uamiName: { defaultValue: '', type: 'string' },
  requestsSiteUrl: { defaultValue: '', type: 'string' },
  spoRootSiteUrl: { defaultValue: '', type: 'string' },
  requestsSettingsListId: { defaultValue: '', type: 'string' },
  governanceListId: { defaultValue: '', type: 'string' },
  governanceLogListId: { defaultValue: '', type: 'string' },
};

// Marker for strings that ARM must evaluate. Every other string that happens to
// start with '[' is escaped to '[[' so ARM leaves it alone.
const ARM = (s) => ({ __arm: s });

function connection(key, name, api) {
  return {
    [key]: {
      connectionId: ARM(`[concat('/subscriptions/',parameters('subscriptionId'),'/resourceGroups/',parameters('resourceGroupName'),'/providers/Microsoft.Web/connections/${name}')]`),
      connectionName: name,
      id: ARM(`[concat('/subscriptions/',parameters('subscriptionId'),'/providers/Microsoft.Web/locations/',parameters('location'),'/managedApis/${api}')]`),
    },
  };
}
const TEAMS_CONNECTION = connection('teams', 'bestillingsportalen-teams', 'teams');
const O365_CONNECTION = connection('office365', 'bestillingsportalen-o365', 'office365');


function finalize(node) {
  if (Array.isArray(node)) return node.map(finalize);
  if (node && typeof node === 'object') {
    if (Object.prototype.hasOwnProperty.call(node, '__arm')) return node.__arm;
    const out = {};
    for (const [k, v] of Object.entries(node)) out[k] = finalize(v);
    return out;
  }
  if (typeof node === 'string' && node.startsWith('[')) return '[' + node;
  return node;
}

function template({ name, description, extraArmParams = {}, wfParams = {}, connections = {}, triggers, actions }) {
  const definitionParams = { $connections: { defaultValue: {}, type: 'Object' } };
  for (const [k, armExpr] of Object.entries(wfParams)) {
    definitionParams[k] = { defaultValue: ARM(armExpr), type: 'String' };
  }
  const resource = {
    comments: description,
    type: 'Microsoft.Logic/workflows',
    apiVersion: '2017-07-01',
    name,
    location: ARM("[parameters('location')]"),
    properties: {
      state: 'Enabled',
      definition: {
        $schema: 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#',
        contentVersion: '1.0.0.0',
        parameters: definitionParams,
        triggers,
        actions,
        outputs: {},
      },
      parameters: { $connections: { value: connections } },
    },
  };
  const tpl = {
    $schema: 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#',
    contentVersion: '1.0.0.0',
    parameters: { ...ARM_PARAMS, ...extraArmParams },
    variables: {
      uamiId: ARM("[resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', parameters('uamiName'))]"),
    },
    resources: [resource],
  };
  const out = finalize(tpl);
  // Object keys are never escaped by finalize(), so the identity is added afterwards.
  const r = out.resources[0];
  out.resources[0] = { comments: r.comments, type: r.type, apiVersion: r.apiVersion, name: r.name, location: r.location,
    identity: { type: 'UserAssigned', userAssignedIdentities: { "[variables('uamiId')]": {} } }, properties: r.properties };
  return out;
}

// ---------------------------------------------------------------- action helpers
// Actions are built as ordered lists and chained: each action runs after the
// previous one unless it sets its own runAfter.
function seq(list, firstRunAfter = {}) {
  const out = {};
  let prev = null;
  for (const [name, action] of list) {
    if (!action.runAfter) action.runAfter = prev ? { [prev]: ['Succeeded'] } : firstRunAfter;
    out[name] = action;
    prev = name;
  }
  return out;
}
const after = (name, ...status) => ({ [name]: status.length ? status : ['Succeeded'] });

const MI_GRAPH = { audience: 'https://graph.microsoft.com', identity: ARM("[variables('uamiId')]"), type: 'ManagedServiceIdentity' };
const MI_SPO = { audience: ARM("[parameters('spoRootSiteUrl')]"), identity: ARM("[variables('uamiId')]"), type: 'ManagedServiceIdentity' };

const graph = (method, uri, body) => {
  const a = { type: 'Http', inputs: { method, uri, authentication: MI_GRAPH } };
  if (body !== undefined) {
    a.inputs.headers = { 'Content-Type': 'application/json' };
    a.inputs.body = body;
  }
  return a;
};

const SP_JSON = 'application/json;odata=nometadata';
const listUrl = (listParam) => `@{parameters('SiteUrl')}/_api/web/lists(guid'@{parameters('${listParam}')}')`;

const spGet = (uri, queries) => ({ type: 'Http', inputs: { method: 'GET', uri, ...(queries ? { queries } : {}), headers: { Accept: SP_JSON }, authentication: MI_SPO } });
const spCreate = (listParam, body) => ({
  type: 'Http',
  inputs: { method: 'POST', uri: `${listUrl(listParam)}/items`, headers: { Accept: SP_JSON, 'Content-Type': SP_JSON }, body, authentication: MI_SPO },
});
const spUpdate = (listParam, idExpr, body) => ({
  type: 'Http',
  inputs: {
    method: 'POST',
    uri: `${listUrl(listParam)}/items(${idExpr})`,
    headers: { Accept: SP_JSON, 'Content-Type': SP_JSON, 'IF-MATCH': '*', 'X-HTTP-Method': 'MERGE' },
    body,
    authentication: MI_SPO,
  },
});
const log = (teamIdExpr, teamNameExpr, action, title, details, performedBy = 'System') =>
  spCreate('GovernanceLogListId', {
    Title: title,
    TeamObjectGUID: teamIdExpr,
    TeamName: teamNameExpr,
    LogAction: action,
    LogDetails: details,
    PerformedBy: performedBy,
  });

const compose = (inputs) => ({ type: 'Compose', inputs });
const query = (from, where) => ({ type: 'Query', inputs: { from, where } });
const select = (from, sel) => ({ type: 'Select', inputs: { from, select: sel } });
const setVar = (name, value) => ({ type: 'SetVariable', inputs: { name, value } });
const initVars = (vars) => ({ type: 'InitializeVariable', inputs: { variables: vars } });
const cond = (expression, actions, elseActions) => {
  const a = { type: 'If', expression, actions: actions || {} };
  if (elseActions) a.else = { actions: elseActions };
  return a;
};
const scope = (actions) => ({ type: 'Scope', actions });
const foreach = (from, actions, concurrency = 5) => ({
  type: 'Foreach',
  foreach: from,
  actions,
  runtimeConfiguration: { concurrency: { repetitions: concurrency } },
});
const terminate = (status = 'Succeeded') => ({ type: 'Terminate', inputs: { runStatus: status } });

// SharePoint REST pagination into an array variable.
// Returns [name, action] tuples for a scope that fills `varName`.
function spGetAllScope(prefix, firstUri, varName) {
  const next = `${varName}NextLink`;
  return scope(
    seq([
      [`Get_${prefix}_page`, spGet(firstUri)],
      [`Set_${varName}`, setVar(varName, `@body('Get_${prefix}_page')?['value']`)],
      [`Set_${next}`, setVar(next, `@{coalesce(body('Get_${prefix}_page')?['odata.nextLink'], '')}`)],
      [
        `Until_all_${prefix}_pages`,
        {
          type: 'Until',
          expression: `@equals(variables('${next}'), '')`,
          limit: { count: 200, timeout: 'PT2H' },
          actions: seq([
            [`Get_next_${prefix}_page`, spGet(`@{variables('${next}')}`)],
            [`Union_${prefix}`, compose(`@union(variables('${varName}'), body('Get_next_${prefix}_page')?['value'])`)],
            [`Update_${varName}`, setVar(varName, `@outputs('Union_${prefix}')`)],
            [`Update_${next}`, setVar(next, `@{coalesce(body('Get_next_${prefix}_page')?['odata.nextLink'], '')}`)],
          ]),
        },
      ],
    ])
  );
}

// Governance settings from 'Provisioning Request Settings' -> one object output
// 'Settings'. Values are JSON-escaped via string(createArray(x)) so quotes or
// backslashes in a value cannot break the object.
const jsonStr = (x) => `substring(string(createArray(${x})), 1, sub(length(string(createArray(${x}))), 2))`;
function settingsActions() {
  return [
    [
      'Get_settings',
      spGet(`${listUrl('SettingsListId')}/items`, {
        $select: 'Title,Value',
        $top: '500',
        $filter: "startswith(Title,'Governance') or Title eq 'EnableExpirationDate'",
      }),
    ],
    ['Filter_settings_with_value', query("@body('Get_settings')?['value']", "@not(empty(trim(coalesce(item()?['Value'], ''))))")],
    [
      'Select_settings',
      select("@body('Filter_settings_with_value')", `@concat(${jsonStr("item()?['Title']")}, ':', ${jsonStr("trim(item()?['Value'])")})`),
    ],
    ['Settings', compose("@json(concat('{', join(body('Select_settings'), ','), '}'))")],
  ];
}
const S = (key, def) => `coalesce(outputs('Settings')?['${key}'], '${def}')`;
const SB = (key, def = 'false') => `equals(toLower(${S(key, def)}), 'true')`;
const SI = (key, def) => `int(${S(key, def)})`;

// Localised text. Default language nb-no; nn-no and en-us are alternatives.
const esc = (s) => s.replace(/'/g, "''");
const tExpr = (langExpr, nb, nn, en) =>
  `if(equals(${langExpr},'nn-no'),'${esc(nn)}',if(equals(${langExpr},'en-us'),'${esc(en)}','${esc(nb)}'))`;

module.exports = {
  ARM, template, seq, after, graph, spGet, spCreate, spUpdate, log, listUrl, compose, query, select, setVar, initVars,
  cond, scope, foreach, terminate, spGetAllScope, settingsActions, S, SB, SI, tExpr, esc, TEAMS_CONNECTION, O365_CONNECTION,
};
