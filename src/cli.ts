#!/usr/bin/env node
import { RESEARCH_JOB_KINDS } from "./jobs.js";

const [, , cmd] = process.argv;

if (cmd === "kinds") {
  process.stdout.write(RESEARCH_JOB_KINDS.join("\n") + "\n");
  process.exit(0);
}

process.stderr.write(
  "li-research-ingest R0 stub — use: li-research-ingest kinds\n"
);
process.exit(1);
