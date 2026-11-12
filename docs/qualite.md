# Gazette — Qualité des articles (TD 4)

**État :** document initial de cadrage des règles, à compléter au fil de l'implémentation du TD 4.  
**Jeu de référence :** `articles_export.csv` (299 articles uniques exportés depuis les données brutes, répartis entre six sources).  
**Principe éditorial :** préserver les articles d'actualité ; exclure seulement les contenus clairement hors périmètre, les anomalies bloquantes et les doublons **parfaitement identiques au sein d'une même source**.

## 1. Objectif et périmètre

Les flux RSS sont d'abord conservés dans `articles_bruts/` et indexés dans PostgreSQL (`articles_bruts_index`). Le TD 4 ajoute une **normalisation**, des **règles d'exclusion explicables**, une table `articles_propres`, une table `rejets`, un **rapport de qualité** après chaque passage et des **contrôles assortis d'alertes**.

Le nettoyage ne supprime **jamais** les fichiers bruts. Tout article rejeté reste traçable jusqu'à son JSON d'origine et à son média. Il pourra être réévalué si une règle change.

### Règle de conservation des sujets similaires

- Deux sources différentes peuvent couvrir le **même événement** : **on conserve les deux articles**, même si leurs titres sont identiques.
- Dans une même source, deux titres proches mais non identiques sont **conservés**.
- Un doublon n'est rejeté que lorsque, **dans une même source**, le **titre normalisé et le contenu normalisé (résumé)** sont exactement identiques à ceux d'un article déjà retenu. On conserve une version et on trace la seconde comme rejetée. Cette règle évite de confondre « même sujet » et « même article ».
- La détection de doublons approximatifs (Jaccard ou distance d'édition) demandée par l'énoncé n'est **pas implémentée dans cette première version** : ce choix privilégie la limitation des faux positifs. Il doit être présenté comme une **limite / adaptation au sujet** dans le rendu.

## 2. Reprise des données et exemples observés

### Inventaire de l'export analysé

| Source | Articles dans l'export |
|---|---:|
| Libération | 102 |
| FranceInfo | 66 |
| L'Humanité | 41 |
| Le Monde | 34 |
| Ouest-France | 32 |
| La Provence | 24 |
| **Total** | **299** |

Il s'agit d'un **instantané** du CSV fourni, et non du nombre d'articles ingérés lors d'un cycle particulier. Sud Ouest et Le Télégramme n'ont pas d'articles dans cet export.

### Deux contenus problématiques identifiés

| Source | Article observé | Problème | Décision proposée | Identifiant |
|---|---|---|---|---|
| Ouest-France | « QUIZ. Expressions, conjugaison, ponctuation… ne commettez plus les erreurs courantes ! » | Quiz : activité ludique hors du contenu d'actualité retenu | Rejeter | `R04_jeux_concours` |
| L'Humanité | « Début de direct » | Titre non informatif, ne décrit pas une actualité identifiable | Rejeter si le titre est exactement celui-ci après normalisation | `R09_titre_generique` |

**Références des items bruts :**

- Quiz Ouest-France : `621b6201873ce733a4d9fcd99d74648404195c5c236bc80426d9b9fa4bc448f9`
- « Début de direct » (L'Humanité) : `36f8b82ad5b18929d210146b071743879ad4b9aecf738e05f95c79768406ebe0`

Le premier filtrage automatique du CSV a rejeté **un article**, le quiz. Le second exemple est une **règle éditoriale supplémentaire retenue pour le TD 4**, à implémenter et à revalider ; il ne faut pas affirmer que deux rejets ont déjà été produits par le pipeline.

L'énoncé suggère dix pollueurs ; **seuls ces deux exemples sont retenus comme suffisamment clairs à ce stade**. Les autres catégories restent couvertes par des règles et des tests synthétiques, sans inventer d'observations sur le CSV.

## 3. Normalisation avant filtrage

Les transformations doivent être des **fonctions pures** et chacune doit avoir au moins un test unitaire :

1. **HTML** : enlever les balises des titres/résumés sans concaténer accidentellement les mots ; décoder `&nbsp;`, `&#39;`, etc.
2. **Espaces** : remplacer les espaces insécables, espaces multiples et retours à la ligne par une présentation cohérente.
3. **Encodage** : détecter des séquences suspectes comme `Ã©` ; ne corriger que lorsque la réparation est sûre. Sinon, signaler l'article pour rejet/contrôle.
4. **Dates** : convertir les dates interprétables en UTC ; garder une trace de la date brute et gérer explicitement les valeurs absentes ou invalides.
5. **Extrait** : enlever le HTML et borner sa longueur conformément au contrat de données (plafond à préciser pour la couche propre ; le brut est déjà limité à 2 000 caractères).
6. **Traçabilité** : ne pas modifier l'`id`, le `lien`, la `source` ou la référence au fichier JSON brut.

Le texte normalisé sert au filtrage et au stockage propre. **Le JSON brut reste intact.**

## 4. Règles d'exclusion prévues

Les règles sont évaluées dans un **ordre stable** ; un rejet est enregistré avec son identifiant principal. Si plusieurs règles s'appliquent, on peut enregistrer également les règles secondaires pour l'analyse, sans compter deux fois le même item dans le total des rejets.

| ID | Règle | Critère prudent | Pourquoi | Exemple / test |
|---|---|---|---|---|
| `R01_publi` | Publicité / partenariat | Mentions explicites « contenu partenaire », « publi-reportage », « sponsorisé » dans un contexte éditorial | Éviter les contenus promotionnels | Titre fictif de fixture : « Contenu partenaire — Offre X » |
| `R02_horoscope` | Horoscope | Rubrique ou titre explicitement identifié comme horoscope | Hors périmètre | Fixture : « Horoscope du jour » |
| `R03_programme_tv` | Programme TV | Titre/rubrique annonçant un programme ou une grille TV, pas un reportage sur la télévision | Hors périmètre | Fixture : « Programme TV de ce soir » |
| `R04_jeux_concours` | Jeux / quiz / concours | Article correspondant explicitement à un quiz, sudoku, mots croisés ou jeu-concours | Écarter les contenus de divertissement non éditoriaux | Quiz Ouest-France observé |
| `R05_titre_vide` | Titre vide | Titre vide après normalisation | Article inexploitable | Fixture : `"titre": "  "` |
| `R06_date_future` | Date incohérente | Date de publication supérieure à la date de contrôle, avec tolérance technique documentée (proposition : 5 min) | Éviter les dates impossibles | Fixture datée du lendemain |
| `R07_encodage` | Encodage irrécupérable | Texte manifestement corrompu et non réparable avec confiance | Éviter un affichage illisible | Fixture : `"ActualitÃ©"` après tentative de réparation |
| `R08_doublon_exact` | Doublon parfait | **Même source**, même titre normalisé **et** même résumé normalisé qu'un autre article déjà retenu | Ne conserver qu'une version identique | Deux fixtures d'une même source au titre et résumé identiques |
| `R09_titre_generique` | Titre générique | Liste fermée et révisable, commençant par « Début de direct » (égalité après normalisation) | Titre insuffisant pour une gazette | L'Humanité observé |

### Garde-fous contre les faux positifs

- « Jeux vidéo » dans une actualité **n'est pas** un quiz à rejeter.
- Un article **sur** la publicité ou la télévision n'est pas nécessairement publicitaire ni un programme TV.
- Deux articles d'auteurs/sources différents sur un même événement ne sont **pas** des doublons à supprimer.
- Deux titres proches (un ou deux mots différents) **ne sont pas rejetés**.
- Une date absente n'est pas automatiquement une « date future » ; elle est remontée comme donnée manquante dans les métriques et doit recevoir une politique distincte si nécessaire.

**État de mise en œuvre :** ces règles constituent le **contrat fonctionnel prévu** ; leur intégration dans `src/gazette/processing/rules.py`, les tests et le pipeline PostgreSQL/Airflow reste à réaliser et à valider.

## 5. Contrôles qualité sur les données réelles

Après chaque traitement, la tâche de contrôle du DAG vérifiera au minimum :

| Contrôle | Critère / seuil | Comportement si anomalie |
|---|---|---|
| Titres valides | Aucun titre vide dans `articles_propres` | Échec de contrôle + alerte |
| Dates cohérentes | Aucune publication future dans `articles_propres`, selon la tolérance retenue | Échec de contrôle + alerte |
| Rejets par source | Taux de rejet **≤ 80 %** par source disposant d'items examinés | Alerte avec source, total et motif ; zéro item = non applicable |
| Doublons interdits | Aucun doublon parfait selon la règle `R08` dans une même source | Échec de contrôle + alerte |
| Traçabilité | Chaque article propre et chaque rejet pointe vers un item brut existant | Échec de contrôle + alerte |

Ces contrôles portent sur **les données produites en exploitation**, pas uniquement sur les jeux d'essai de la CI. Leurs chiffres sont publiés dans les logs/métriques de l'orchestrateur (ou sur un endpoint ultérieur). Un canal réellement consulté par l'équipe (Discord, Slack ou e-mail) devra recevoir **au moins une alerte de test vérifiée**. Le canal et la preuve de réception sont **à renseigner**.

## 6. Rapport de qualité attendu

Chaque passage doit générer un bilan traçable par identifiant d'exécution ; un rapport du jour agrège ou référence les passages, par exemple `rapports/qualite-YYYY-MM-DD.md`.

Le rapport doit comprendre :

- Horodatage UTC et identifiant du passage Airflow.
- Nombre d'items **examinés**, **conservés**, **rejetés** et éventuellement **inchangés** (réexaminés mais déjà stockés).
- Rejets ventilés **par source** et **par identifiant de règle**.
- Les **cinq motifs de rejet les plus fréquents**, même si moins de cinq motifs apparaissent.
- Taux de rejet par source, calculé comme `rejetés / examinés` lorsque `examinés > 0`.
- Résultats des contrôles qualité et état des alertes.

L'identité `examinés = conservés + rejetés` doit tenir **pour les décisions de filtrage du passage**. Les nombres de nouvelles insertions en base sont suivis séparément pour ne pas confondre dédoublonnage et réexécution idempotente.

## 7. Stockage, traçabilité et conformité

- **Bruts** : JSON dans `articles_bruts/<source>/<id>.json` et lignes dans `articles_bruts_index` ; aucune suppression lors du filtrage.
- **Propres** : future table PostgreSQL `articles_propres` avec titre, extrait court, lien, source, date et référence à l'item brut.
- **Rejets** : future table `rejets` avec référence à l'item brut, identifiant de règle, motif et date du traitement.
- **Réexécution** : éviter les insertions multiples identiques ; permettre la réévaluation lors d'un changement de règles.
- **Droits et minimisation** : conserver seulement les métadonnées et extraits dont l'usage est autorisé, sans constituer de base de données personnelles ni recopier le texte intégral des articles.
- **Rétention** : politique à **valider et inscrire** dans `docs/donnees.md` avant automatisation de la purge. Proposition de travail : 90 jours pour le brut et stockage froid pour les éditions de plus d'un mois ; **aucune purge n'est actuellement activée par ce document**.

## 8. Tests et preuves à produire

- [ ] Un test par fonction de normalisation.
- [ ] Un test positif et un contre-exemple par règle d'exclusion.
- [ ] Deux articles de sources différentes sur un même sujet sont conservés.
- [ ] Deux articles de la même source avec titres proches mais différents sont conservés.
- [ ] Deux contenus parfaitement identiques de la même source donnent un seul article propre.
- [ ] Migration et stockage dans `articles_propres` / `rejets` testés avec PostgreSQL.
- [ ] Rapport réel généré et archivé après un cycle.
- [ ] Contrôles exécutés après la collecte dans Airflow.
- [ ] Alerte effectivement reçue par l'équipe au moins une fois.
- [ ] Suivi des rapports sur trois matinées et modification justifiée d'une règle avant le TD 5.

## 9. Journal des décisions

| Date | Décision | Justification / preuve |
|---|---|---|
| À dater lors de l'intégration | Conserver les articles traitant du même sujet, y compris inter-sources | Préserver la diversité éditoriale et éviter les faux positifs |
| À dater lors de l'intégration | Limiter le dédoublonnage aux copies parfaites d'une même source | Priorité donnée à la conservation des articles ; dédoublonnage approximatif non couvert |
| À dater lors de l'intégration | Documenter deux pollueurs avérés plutôt que d'en inventer dix | Export de référence de 299 articles ; deux exemples clairement identifiés |

**À compléter après implémentation :** résultats des tests, première date du rapport, seuils ajustés, preuve de l'alerte et politique de rétention validée.
