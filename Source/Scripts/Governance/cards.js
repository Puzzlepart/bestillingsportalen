// Adaptive cards for the Teams governance notifications. Every text is
// localised at runtime (nb-no default, nn-no, en-us) from the language
// expression passed in.
'use strict';
const { tExpr } = require('./lib');

const MANAGE_GUIDE = 'https://support.microsoft.com/office/manage-team-settings-and-permissions-in-microsoft-teams-ce053b04-1b8e-4796-baa8-90dc427b3acc';
const ARCHIVE_GUIDE = 'https://support.microsoft.com/office/archive-or-restore-a-team-dc161cfd-b328-440f-974b-5da5bd98b5a7';

function cards(lang, ctx) {
  // ctx: expressions (without @) for the values used in texts
  const T = (nb, nn, en) => `@{${tExpr(lang, nb, nn, en)}}`;
  const date = (x) => `@{formatDateTime(${x}, 'dd.MM.yyyy')}`;
  const v = (x) => `@{${x}}`;

  const card = (body, actions) => {
    const c = { type: 'AdaptiveCard', $schema: 'http://adaptivecards.io/schemas/adaptive-card.json', version: '1.4', body };
    if (actions) c.actions = actions;
    return c;
  };
  const header = (style, text) => ({
    type: 'Container',
    style,
    items: [{ type: 'TextBlock', text, weight: 'Bolder', size: 'Large', wrap: true }],
  });
  const text = (t, extra = {}) => ({ type: 'TextBlock', text: t, wrap: true, spacing: 'Small', ...extra });
  const facts = (list) => ({ type: 'FactSet', facts: list.map(([title, value]) => ({ title, value })) });

  const teamFact = ['Team:', v(ctx.teamName)];
  const ownersFact = [T('Eiere:', 'Eigarar:', 'Owners:'), v(ctx.owners)];
  const endDateFact = [T('Sluttdato:', 'Sluttdato:', 'End date:'), date(ctx.endDate)];

  // Links block - the organisation's own guide is shown only when configured.
  const links = {
    type: 'Container',
    spacing: 'Medium',
    items: [
      text(T('📖 **Nyttige lenker**', '📖 **Nyttige lenker**', '📖 **Useful links**')),
      {
        type: 'TextBlock',
        wrap: true,
        spacing: 'None',
        isVisible: `@not(empty(${ctx.guideUrl}))`,
        text: `${T('• [Retningslinjer for Teams', '• [Retningslinjer for Teams', '• [Teams guidelines')}](${v(ctx.guideUrl)})`,
      },
      text(`${T('• [Slik administrerer du et team', '• [Slik administrerer du eit team', '• [How to manage a team')}](${MANAGE_GUIDE})`, { spacing: 'None' }),
      text(`${T('• [Slik arkiverer eller gjenoppretter du et team', '• [Slik arkiverer eller gjenopprettar du eit team', '• [How to archive or restore a team')}](${ARCHIVE_GUIDE})`, { spacing: 'None' }),
    ],
  };

  const tidyUp = {
    type: 'Container',
    spacing: 'Medium',
    items: [
      text(T('🧹 **Ryddetips**', '🧹 **Ryddetips**', '🧹 **Tidy-up tips**')),
      text(T('• Sjekk at eierne er riktige - et team bør ha minst to eiere.', '• Sjekk at eigarane er rette - eit team bør ha minst to eigarar.', '• Check that the owners are correct - a team should have at least two owners.'), { spacing: 'None' }),
      text(T('• Fjern medlemmer som ikke lenger trenger tilgang.', '• Fjern medlemmar som ikkje lenger treng tilgang.', '• Remove members who no longer need access.'), { spacing: 'None' }),
      text(T('• Slett gamle filer og samtaler, og arkiver dokumenter med arkivverdi i sak-/arkivsystemet.', '• Slett gamle filer og samtalar, og arkiver dokument med arkivverdi i sak-/arkivsystemet.', '• Delete old files and conversations, and file records in your records management system.'), { spacing: 'None' }),
    ],
  };

  const deletionNote = `@{if(${ctx.deletionEnabled}, ${tExpr(lang,
    ' Deretter blir det slettet automatisk etter ',
    ' Deretter blir det sletta automatisk etter ',
    ' It will then be deleted automatically after ')}, '')}@{if(${ctx.deletionEnabled}, concat(string(${ctx.deleteAfterDays}), ${tExpr(lang, ' dager.', ' dagar.', ' days.')}), '')}`;

  const endDateInput = {
    type: 'Input.Date',
    id: 'newEndDate',
    label: T('Ny sluttdato', 'Ny sluttdato', 'New end date'),
    isRequired: true,
    errorMessage: T('Velg en ny sluttdato', 'Vel ein ny sluttdato', 'Please select a new end date'),
    min: `@{formatDateTime(addDays(utcNow(), 1), 'yyyy-MM-dd')}`,
  };
  const extendAction = { type: 'Action.Submit', title: T('📅 Forleng sluttdato', '📅 Forleng sluttdato', '📅 Extend end date'), style: 'positive', data: { actionId: 'extend' } };
  const endAction = (id) => ({ type: 'Action.Submit', title: T('Avslutt teamet', 'Avslutt teamet', 'End the team'), associatedInputs: 'none', data: { actionId: id } });
  const keepAction = { type: 'Action.Submit', title: T('✅ Bruk teamet videre', '✅ Bruk teamet vidare', '✅ Continue using the team'), style: 'positive', data: { actionId: 'still-needed' } };

  const endDateBody = (reminder) => [
    header('attention', reminder
      ? T('🔔 PÅMINNELSE: Teamet ditt går snart ut', '🔔 PÅMINNING: Teamet ditt går snart ut', '🔔 REMINDER: Your team is expiring soon')
      : T('⚠️ Teamet ditt går snart ut', '⚠️ Teamet ditt går snart ut', '⚠️ Your team is expiring soon')),
    facts([teamFact, endDateFact, ownersFact]),
    text(`${T('Teamet **', 'Teamet **', 'The team **')}${v(ctx.teamName)}${T('** har sluttdato **', '** har sluttdato **', '** has an end date of **')}${date(ctx.endDate)}**.`, { spacing: 'Medium' }),
    text(T('Hvis du trenger teamet videre, må du forlenge sluttdatoen.', 'Dersom du treng teamet vidare, må du forlenge sluttdatoen.', 'If you still need the team, you must extend the end date.')),
    text(`${reminder
      ? T('Hvis sluttdatoen ikke forlenges, blir teamet arkivert (låst for endringer) etter sluttdatoen.', 'Dersom sluttdatoen ikkje blir forlengd, blir teamet arkivert (låst for endringar) etter sluttdatoen.', 'If the end date is not extended, the team will be archived (locked for changes) after the end date.')
      : T('Hvis du avslutter teamet, blir det arkivert (låst for endringer) når sluttdatoen er passert.', 'Dersom du avsluttar teamet, blir det arkivert (låst for endringar) når sluttdatoen er passert.', 'If you end the team, it will be archived (locked for changes) once the end date has passed.')}${deletionNote}`),
    endDateInput,
    links,
  ];

  const reviewBody = (reminder) => [
    header('accent', reminder
      ? T('🔔 PÅMINNELSE: Årlig gjennomgang av teamet ditt', '🔔 PÅMINNING: Årleg gjennomgang av teamet ditt', '🔔 REMINDER: Annual review of your team')
      : T('📋 Årlig gjennomgang av teamet ditt', '📋 Årleg gjennomgang av teamet ditt', '📋 Annual review of your team')),
    facts([teamFact, [T('Opprettet:', 'Oppretta:', 'Created:'), date(ctx.createdDate)], ownersFact]),
    text(`${T('Det er tid for den årlige gjennomgangen av teamet **', 'Det er tid for den årlege gjennomgangen av teamet **', 'It is time for the annual review of the team **')}${v(ctx.teamName)}**.`, { spacing: 'Medium' }),
    tidyUp,
    text(T('Når du har sjekket eiere og ryddet, velg ett av valgene nedenfor. **Avslutt teamet** arkiverer teamet med én gang (låst for endringer). Eiere kan selv gjenopprette et arkivert team.', 'Når du har sjekka eigarar og rydda, vel eitt av vala nedanfor. **Avslutt teamet** arkiverer teamet med ein gong (låst for endringar). Eigarar kan sjølve gjenopprette eit arkivert team.', 'Once you have checked the owners and tidied up, choose one of the options below. **End the team** archives the team immediately (locked for changes). Owners can restore an archived team themselves.'), { spacing: 'Medium' }),
    reminder && text(T('⚠️ Hvis ingen svarer, blir teamet arkivert automatisk.', '⚠️ Dersom ingen svarar, blir teamet arkivert automatisk.', '⚠️ If nobody responds, the team will be archived automatically.')),
    links,
  ].filter(Boolean);

  // Resolved versions replace the interactive card once someone has responded.
  const responder = v(ctx.responder);
  const resolved = {
    extended: card([
      header('good', T('✅ Sluttdatoen er forlenget', '✅ Sluttdatoen er forlengd', '✅ End date extended')),
      facts([teamFact, [T('Opprinnelig sluttdato:', 'Opphavleg sluttdato:', 'Original end date:'), date(ctx.endDate)], [T('Ny sluttdato:', 'Ny sluttdato:', 'New end date:'), date(ctx.newEndDate)], [T('Forlenget av:', 'Forlengd av:', 'Extended by:'), responder]]),
      text(T('Du får et nytt varsel før den nye sluttdatoen.', 'Du får eit nytt varsel før den nye sluttdatoen.', 'You will be notified again before the new end date.'), { spacing: 'Medium' }),
      tidyUp,
      links,
    ]),
    noExtension: card([
      header('default', T('ℹ️ Teamet avsluttes på sluttdatoen', 'ℹ️ Teamet blir avslutta på sluttdatoen', 'ℹ️ The team will end on the end date')),
      facts([teamFact, endDateFact, [T('Besvart av:', 'Svara av:', 'Responded by:'), responder]]),
      text(T('En eier har bestemt at teamet skal arkiveres når sluttdatoen er passert. Lagre det dere trenger før det.', 'Ein eigar har bestemt at teamet skal arkiverast når sluttdatoen er passert. Lagre det de treng før det.', 'An owner has decided that the team will be archived once the end date has passed. Save anything you need before then.'), { spacing: 'Medium' }),
      tidyUp,
      links,
    ]),
    stillNeeded: card([
      header('good', T('✅ Årlig gjennomgang fullført', '✅ Årleg gjennomgang fullført', '✅ Annual review complete')),
      facts([teamFact, [T('Gjennomgått av:', 'Gjennomgått av:', 'Reviewed by:'), responder]]),
      text(T('Teamet er bekreftet som aktivt. Neste gjennomgang kommer om ett år.', 'Teamet er stadfesta som aktivt. Neste gjennomgang kjem om eitt år.', 'The team is confirmed as active. The next review is in one year.'), { spacing: 'Medium' }),
      tidyUp,
      links,
    ]),
    archived: card([
      header('default', T('📁 Teamet er arkivert', '📁 Teamet er arkivert', '📁 Team archived')),
      facts([teamFact, [T('Avsluttet av:', 'Avslutta av:', 'Ended by:'), responder]]),
      text(T('En eier har bekreftet at teamet ikke lenger trengs, og teamet er arkivert (låst for endringer). Var dette en feil, kan eierne gjenopprette teamet selv.', 'Ein eigar har stadfesta at teamet ikkje lenger trengst, og teamet er arkivert (låst for endringar). Var dette ein feil, kan eigarane gjenopprette teamet sjølve.', 'An owner confirmed that the team is no longer needed, and it has been archived (locked for changes). If this was a mistake, the owners can restore the team themselves.'), { spacing: 'Medium' }),
      links,
    ]),
    alreadyGone: card([
      header('default', T('ℹ️ Teamet finnes ikke lenger', 'ℹ️ Teamet finst ikkje lenger', 'ℹ️ The team no longer exists')),
      facts([teamFact, [T('Besvart av:', 'Svara av:', 'Responded by:'), responder]]),
      text(T('Teamet var allerede slettet da svaret kom inn.', 'Teamet var allereie sletta då svaret kom inn.', 'The team had already been deleted when the response arrived.'), { spacing: 'Medium' }),
    ]),
  };

  const expired = card([
    header('warning', T('⏰ Varselet har utløpt', '⏰ Varselet har gått ut', '⏰ The notification has expired')),
    facts([teamFact]),
    text(T('Vi fikk ikke svar på et tidligere varsel om dette teamet innen fristen, og knappene i det virker ikke lenger. Bruk det nyeste varselet i chatten.', 'Vi fekk ikkje svar på eit tidlegare varsel om dette teamet innan fristen, og knappane i det verkar ikkje lenger. Bruk det nyaste varselet i chatten.', 'An earlier notification about this team was not answered in time, and its buttons no longer work. Please use the latest notification in this chat.'), { spacing: 'Medium' }),
  ]);

  return {
    enddateFirst: card(endDateBody(false), [extendAction, endAction('no-extension')]),
    enddateReminder: card(endDateBody(true), [extendAction]),
    annualReview: card(reviewBody(false), [keepAction, endAction('not-needed')]),
    annualReviewReminder: card(reviewBody(true), [keepAction, endAction('not-needed')]),
    resolved,
    expired,
    links,
    header,
    text,
    facts,
    card,
    T,
    date,
    v,
  };
}

module.exports = { cards, MANAGE_GUIDE, ARCHIVE_GUIDE };
