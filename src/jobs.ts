/** Research job kinds — mirrors lidb.research_job.kind CHECK. */
export const RESEARCH_JOB_KINDS = [
  "ingest_batch",
  "index_citations",
  "reindex_paper",
] as const;

export type ResearchJobKind = (typeof RESEARCH_JOB_KINDS)[number];
