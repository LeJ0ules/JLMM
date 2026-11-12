-- TD4 : une décision courante par article brut, avec traçabilité.
-- Ne pas modifier 001_sources_articles.sql déjà appliquée.
CREATE TABLE articles_propres (
    article_brut_id CHAR(64) PRIMARY KEY REFERENCES articles_bruts_index(id) ON DELETE RESTRICT,
    source TEXT NOT NULL REFERENCES sources(id),
    empreinte_contenu CHAR(64) NOT NULL,
    titre TEXT NOT NULL CHECK (length(btrim(titre)) > 0),
    resume TEXT NOT NULL DEFAULT '',
    lien TEXT NOT NULL,
    publie_le TIMESTAMPTZ,
    recupere_le TIMESTAMPTZ NOT NULL,
    rubrique JSONB NOT NULL DEFAULT '[]'::jsonb,
    traite_le TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (source, empreinte_contenu)
);

CREATE TABLE rejets (
    article_brut_id CHAR(64) PRIMARY KEY REFERENCES articles_bruts_index(id) ON DELETE RESTRICT,
    source TEXT NOT NULL REFERENCES sources(id),
    regle_id TEXT NOT NULL CHECK (length(btrim(regle_id)) > 0),
    motif TEXT NOT NULL,
    traite_le TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_articles_propres_source ON articles_propres(source);
CREATE INDEX idx_rejets_source_regle ON rejets(source, regle_id);
