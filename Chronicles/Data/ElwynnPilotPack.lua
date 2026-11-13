local MS = _G.MS

-- Published frFR content.
-- Editorial QuestIDs beyond the trigger are references, not runtime conditions.
MS.ChroniclesElwynnPilotPack = {
    contentSchemaVersion = 1,
    pack = { id = "journey.elwynn.pilot.v1", version = 1,
        source = "COMMUNITY_CURATED", timeline = "classic_forever" },
    regions = {
        { id = "elwynn", contentVersion = 1, mapID = 1429,
            names = { enUS = "Elwynn Forest" } },
    },
    chronicles = {
        { id = "elwynn.goldshire.01", contentVersion = 1, status = "PUBLISHED",
            format = "CHRONICLE", type = "PLACE", region = "elwynn",
            locales = {
                frFR = { status = "PUBLISHED", title = "Comté-de-l’Or",
                    body = [=[À Comté-du-Nord, les dangers semblaient encore proches et contenus. Une abbaye, quelques fermes, une mine à surveiller. Même les kobolds de la Crête aux échos donnaient l’impression d’un problème que l’on pouvait circonscrire avec assez de courage et quelques bonnes lames.

La route vers Comté-de-l’Or change cette impression.

Le maréchal McBride n’y envoie pas simplement un messager. Après les troubles de Comté-du-Nord, il estime que vous pouvez désormais être utile au-delà de la vallée. À Comté-de-l’Or, le maréchal Dughan vous confie à son tour une part de cette responsabilité.

La forêt d’Elwynn paraît paisible au premier regard : des chemins fréquentés, des fermes, des voyageurs qui passent sous les murs de Hurlevent. Pourtant, ceux qui sont chargés de sa sécurité n’ont pas assez d’hommes pour être partout.

C’est peut-être cela que marque réellement votre arrivée ici.

Comté-du-Nord était un commencement. À présent, la route s’élargit, les distances aussi, et chaque problème rencontré semble pouvoir en cacher un autre un peu plus loin.

Pour la première fois, votre aventure ne se limite plus à défendre un coin de vallée.

Elle commence à ressembler à la défense d’un royaume.]=] },
                enUS = { status = "MISSING" },
            },
            trigger = { type = "QUEST_COMPLETED", questID = 54 },
            spoiler = { policy = "DISCOVERY_SAFE" },
            sources = {
                { type = "SECONDARY_REFERENCE", reference = "60.tools — quête 54, `Report to Goldshire`, présente dans le client Forever build 1.60.1.70124 ; trajet McBride → Dughan, responsabilité sur Elwynn et statut d’adjoint." },
                { type = "OTHER", reference = "Observation directe utilisateur : **Comté-de-l’Or** et **Comté-du-Nord** confirmés dans le client frFR." },
                { type = "OTHER", reference = "UiMapID 1429 = Elwynn Forest." },
                { type = "SECONDARY_REFERENCE", reference = "Wowhead frFR — quête 54, `Rapport pour Comté-de-l’Or`, localisation historique compatible et texte cohérent avec la version Forever." },
            },
            credits = { author = "Olirakith", contributors = {} },
        },
        { id = "elwynn.fargodeep.01", contentVersion = 1, status = "PUBLISHED",
            format = "CHRONICLE", type = "QUEST_STORY", region = "elwynn",
            locales = {
                frFR = { status = "PUBLISHED", title = "Mine de Fondugouffre",
                    body = [=[Sous la terre, l’air a quelque chose de familier.

À Comté-du-Nord, les kobolds occupaient déjà les galeries de la Crête aux échos. On aurait pu croire le problème lié à cette vallée, à cette mine, à ce premier coin d’Elwynn où votre aventure a commencé.

Fondugouffre détruit cette illusion.

Le maréchal Dughan avait reçu des rapports inquiétants et vous a demandé de les vérifier. Cette fois, il ne s’agissait pas de repousser quelques créatures aperçues près d’une route. Il fallait descendre dans la mine et voir de vos propres yeux ce qui se cachait sous les collines au sud de Comté-de-l’Or.

Les rapports disaient vrai.

Les kobolds sont là.

La découverte n’apporte pourtant aucune réponse. Elle pose surtout une nouvelle question : pourquoi retrouver la même menace dans deux mines éloignées l’une de l’autre ?

Dughan ne semble pas davantage rassuré par votre retour. Les patrouilles devront être renforcées autour de Fondugouffre, signe que la mine n’est plus seulement le problème de ceux qui y travaillaient autrefois.

Comté-du-Nord pouvait encore ressembler à un incident.

À Fondugouffre, une inquiétude commence à prendre forme : sous les chemins tranquilles de la forêt d’Elwynn, quelque chose s’étend peut-être plus loin que prévu.]=] },
                enUS = { status = "MISSING" },
            },
            trigger = { type = "QUEST_COMPLETED", questID = 62 },
            spoiler = { policy = "DISCOVERY_SAFE" },
            sources = {
                { type = "SECONDARY_REFERENCE", reference = "60.tools — quête 62, `The Fargodeep Mine`, présence Forever et texte établissant les rapports, l’exploration et la confirmation des kobolds." },
                { type = "SECONDARY_REFERENCE", reference = "WoW Forever database — q62 observée dans les données du build 1.60.1.70124." },
                { type = "OTHER", reference = "UiMapID 1429 = Elwynn Forest." },
                { type = "SECONDARY_REFERENCE", reference = "Wowhead frFR — `La mine de Fondugouffre`, localisation française et chronologie compatibles." },
            },
            credits = { author = "Olirakith", contributors = {} },
        },
        { id = "elwynn.jasperlode.01", contentVersion = 1, status = "PUBLISHED",
            format = "CHRONICLE", type = "QUEST_STORY", region = "elwynn",
            locales = {
                frFR = { status = "PUBLISHED", title = "Mine Veine-de-jaspe",
                    body = [=[Fondugouffre avait déjà changé la nature du problème.

Veine-de-jaspe le rend impossible à ignorer.

Après votre premier rapport, le maréchal Dughan vous a envoyé plus loin vers l’est, jusqu’aux collines situées au-delà de la tour d’Azora. Il voulait savoir si une autre mine d’Elwynn connaissait les mêmes troubles.

Vous connaissez désormais la réponse.

Les kobolds sont aussi présents à Veine-de-jaspe.

Trois lieux différents racontent ainsi une histoire semblable : les galeries de la Crête aux échos, Fondugouffre, puis cette mine plus éloignée. Rien ne permet encore de dire pourquoi. Peut-être n’existe-t-il même pas une raison unique. Mais à mesure que les mêmes silhouettes réapparaissent sous des collines toujours plus distantes, il devient difficile de parler d’un simple incident local.

Dughan accueille votre rapport sans soulagement. Au contraire, chaque confirmation semble ajouter une nouvelle portion de forêt à surveiller avec des effectifs déjà trop dispersés.

La surface d’Elwynn garde ses chemins, ses fermes et ses voyageurs.

Sous cette apparente tranquillité, les mines racontent une autre histoire.

Et pour l’instant, personne ne sait jusqu’où elle se prolonge.]=] },
                enUS = { status = "MISSING" },
            },
            trigger = { type = "QUEST_COMPLETED", questID = 76 },
            spoiler = { policy = "DISCOVERY_SAFE" },
            sources = {
                { type = "SECONDARY_REFERENCE", reference = "60.tools — q76, `The Jasperlode Mine`, présente dans le client Forever build 1.60.1.70009 ; q62 indiquée comme prérequis et confirmation explicite de kobolds à Veine-de-jaspe." },
                { type = "OTHER", reference = "UiMapID 1429 = Elwynn Forest." },
                { type = "SECONDARY_REFERENCE", reference = "Wowhead frFR — `La mine Veine-de-jaspe`, noms et texte historique compatibles avec les données Forever." },
            },
            credits = { author = "Olirakith", contributors = {} },
        },
        { id = "elwynn.collector.defias.01", contentVersion = 1, status = "PUBLISHED",
            format = "CHRONICLE", type = "QUEST_STORY", region = "elwynn",
            locales = {
                frFR = { status = "PUBLISHED", title = "Le Collecteur",
                    body = [=[Jusqu’ici, les problèmes d’Elwynn avaient un visage facile à reconnaître.

Des kobolds dans les mines. Des gnolls aux lisières. Des routes que les soldats ne peuvent pas surveiller seuls.

Le Collecteur laisse derrière lui quelque chose de différent : des questions.

Tout a commencé avec un plan de route. Des jours, des heures, des livraisons d’or provenant des mines de la forêt. Pourtant, Dughan l’affirme : les gens du royaume n’y travaillent plus depuis des mois.

Quelqu’un extrait donc cet or.

Et quelqu’un le récupère.

La piste vous a conduit jusqu’au Collecteur. Sa mort aurait pu refermer l’affaire, mais l’anneau trouvé sur lui l’a rendue plus étrange encore. Dughan reconnaît le signe de l’ancienne guilde des Maçons de Hurlevent et pose lui-même la question qui reste désormais suspendue : pourquoi des voleurs Défias collectent-ils l’or des mines d’Elwynn ?

Pour la première fois depuis votre départ de Comté-du-Nord, la menace ne semble plus seulement venir de créatures installées trop près des routes et des fermes.

Des hommes déplacent de l’or.

Ils suivent un calendrier.

Ils travaillent pour quelque chose que vous ne comprenez pas encore.

Le Collecteur est mort, mais le mystère qu’il laisse derrière lui ne fait que commencer.]=] },
                enUS = { status = "MISSING" },
            },
            trigger = { type = "QUEST_COMPLETED", questID = 147 },
            spoiler = { policy = "DISCOVERY_SAFE" },
            sources = {
                { type = "SECONDARY_REFERENCE", reference = "60.tools — q123, `The Collector`, présente dans Forever ; plan de livraison d’or, arrêt du travail officiel dans les mines et ignorance initiale de Dughan sur le commanditaire." },
                { type = "SECONDARY_REFERENCE", reference = "60.tools — q147, `Manhunt`, présente dans le client Forever build 1.60.1.70124 et requérant q123 ; anneau des Maçons et mention explicite des Defias Thieves lors de l’achèvement." },
                { type = "SECONDARY_REFERENCE", reference = "Wowhead Forever frFR — `Le collecteur`, localisation française du nom et du plan de route." },
                { type = "SECONDARY_REFERENCE", reference = "Wowhead Classic frFR — q147, `Chasse à l'homme`, conserve la progression Collecteur → anneau des Maçons → question sur les Défias." },
            },
            credits = { author = "Olirakith", contributors = {} },
        },
    },
    rumors = {},
    collections = {},
    seals = {},
}
