-- Enable pgvector so the notebooks vector store can create vector columns,
-- mirroring the CREATE EXTENSION step the cluster runs via its init Job.
CREATE EXTENSION IF NOT EXISTS vector;
