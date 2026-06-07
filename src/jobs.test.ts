import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { RESEARCH_JOB_KINDS } from "./jobs.js";

describe("RESEARCH_JOB_KINDS", () => {
  it("matches OpenAPI job kinds", () => {
    assert.deepEqual(RESEARCH_JOB_KINDS, [
      "ingest_batch",
      "index_citations",
      "reindex_paper",
    ]);
  });
});
