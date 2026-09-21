# Why this skill is shaped the way it is

Research pass: 2026-09-21. 26 sources fetched, 129 claims extracted, 25 put to
adversarial 3-vote verification, 16 confirmed, 9 refuted.

**Every number in this skill lives in this file.** Keep SKILL.md free of them —
the capability figures below are the perishable part and should be re-checked
before being quoted anywhere. Anything here older than ~6 months is stale.

Read the numbers as **evidence of failure modes, not as calibrated rates for
this skill**. Almost every source measures something adjacent: LLMs as
interview respondents, or click prediction on static screenshots, rather than an
agent driving a live app through a UI-automation MCP. Only GUITester measures
the live-agent setting. The extrapolation is conservative — live multi-step
flows are harder than single static clicks — but it is an extrapolation.

## 1 · Role split (SKILL.md step 4)

**Goal-Oriented Masking.** GUITester (ACL 2026 Findings): agents "perceive
functional anomalies as traversable hurdles rather than reportable defects" —
on a dead button the agent "autonomously seeks alternative navigation paths to
reach the goal", rendering the defect "invisible to the quality assurance
pipeline". Its fix is architectural: a Monitor that "focuses solely on capturing
whether an anomaly occurs without attributing its cause" and can terminate the
subtask.

UXAgent (CHI 2025 EA) converges independently on two loops — a fast acting loop
"without much in-depth thinking" and a slow Wonder/Reflect loop over a shared
memory stream.

Calibration: role separation is necessary, not sufficient — GUITester also seeds
test intents into the acting loop. Its loops run concurrently, which a
single-threaded skill cannot do; it transfers as a subagent boundary. Effect is
real but modest: 48.90% F1 (Pass@3) vs 33.35% for SOTA baselines on GUITestBench
(143 tasks / 26 defects), with a 7B driver model — neither a frontier ceiling
nor an independent evaluation.

## 2 · Evidence gate, both directions (SKILL.md step 5)

**False positives.** Guerino et al. on GPT-4o heuristic evaluation: of 111
issues, 27 (24.3%) were false positives — hallucinated issues, "predicted"
issues from a simulated interaction context, and over-generalisation. Concretely
it flagged missing feedback and missing action confirmations "but when testing
the system, these elements were present". Corroborated independently: AI
false-positive rates 17–18% vs 0–14% for human inspectors, same failure mode of
assuming beyond what the screenshots showed.

**False negatives.** GUITester's *Execution-Bias Attribution*: agents show "a
systematic bias toward self-attribution: erroneously assuming that any failure
to trigger a state change stems from their own execution imprecision". The
remedy is evidence comparison over the trajectory plus screenshots with
interaction points marked — **not** a blind retry, which recovers only
17.5–46.2% of false-negative verdicts.

**Why a soft gate fails.** Salminen et al. (AHs 2025) name *Convincing Mimicry*:
fluent narration makes readers trust synthetic output "even when the content
lacks validity", a "dangerous disparity" between perceived and actual
reliability. Note the wording — that disparity is argued, not measured.

## 3 · No behavioral claims (SKILL.md, top)

Five independent primaries converge. UXAgent's five UX-researcher evaluators
"viewed data from LLM Agents as supplementary rather than definitive". NN/g's
paired transcripts show fabricated outcomes: a real learner finished 3 of 7
courses; the synthetic user said "Yes, I completed all the courses I mentioned".

Kuric et al. (12 first-click studies, n=3,431, 45 tasks) found a statistically
significant distribution difference in 53% of tasks and conclude practitioners
"should avoid relying on LLMs as a source of behavioral predictions", because
the mechanism is "semantic heuristics based on co-occurrences of words in text,
which are fundamentally different from mental processing". They describe this as
architecturally inherent and unfixable by prompting, persona or sampling — not
as permanently irreducible.

**The asymmetry that makes this skill viable at all:** the papers positive on
LLM UX work (PerceptUI; Synthetic Heuristic Evaluation, where synthetic
evaluation beat experts on consistency and layout issues) are positive about
exactly this artifact-level heuristic mode — not about behavioral prediction.

## 4 · Forced coverage diversity (SKILL.md step 1, charters.md)

Kuric et al.: click entropy for synthetic participants M=.43 (SD=.19) vs real
M=.61 (SD=.18), z=−4.09, p<.001; unique hotspots M=5.38 vs M=9.00, z=−4.35,
p<.001. Mechanism verbatim: "in most stimuli, there was a single hotspot that
GPT resolved as the 'victor', to which the model attributed the overwhelming
majority of clicks."

Reproduced in the live-agent setting by Agent A/B (1,000 LLM agents vs a 2M-user
A/B test): "humans exhibited more exploratory interaction patterns… while agents
followed more goal-directed trajectories with fewer actions" — though
outcome-level metrics were comparable, which tempers "useless" but confirms
"under-explores".

COI note: the Kuric authors are UXtweak Research, who sell real-user testing.
Data and code are open and the direction is independently corroborated.

## 5 · Personas as constraints, not backstory (charters.md)

Kuric et al.: "Participant personas, chain-of-thought reasoning in GPT, and
different sampling parameters fail to create sensible fidelity improvements
apart from inflating believability." Single-persona runs showed greater
distribution difference in 96% of tasks (χ²=18.92, p<.001) with "extremely low
entropy M = .02" versus a mega-persona baseline. Persona specificity "does not
significantly affect the accuracy… and may even reduce statistical alignment".

Qualifier from the opposing side: PerceptUI reports persona-aware variants
"consistently stronger" — but only with fine-tuning plus reflective prompt
evolution, on rating prediction rather than click fidelity.

## 6 · Session sheet and PROOF (assets/session-sheet.md)

Jonathan Bach, *Session-Based Test Management* (STQE, Nov/Dec 2000): "a session,
not a test case or bug report, is the basic testing work unit"; a session is "an
uninterrupted block of reviewable, chartered test effort", where reviewable
means "a report (called a session sheet) that provides information about what
happened, in a format that can be examined by a third party".

The section list — charter, tester, start time, task breakdown, data files, test
notes, issues, bugs — is taken from that paper unchanged. So is the machine
orientation: sheets were "provided in a tagged text format" scanned by a tool
doing "about eighty syntax and consistency checks on each sheet", including
verifying that every referenced data file exists in the expected directory.
`scripts/validate-session-sheet` is that check, modernised.

PROOF (Past, Results, Obstacles, Outlook, Feelings) is from the same paper, as
is "We experimented with dropping the session debriefings, but that led to poor
session sheets and meaningless metrics" — one team's practitioner anecdote, not
a study, and not demonstrated to transfer to LLM agents. The 90-minute box is
explicitly soft: "we don't want to be more obsessed with time than with good
testing".

## 7 · Applicability boundary (SKILL.md, hard rules)

Salminen, Amin, Jung & Jansen (AHs 2025) print a boxed guideline — "DO (POSSIBLY)
USE: For existing, well-known products with existing, well-known requirements to
pilot test user research plans"; "DO NOT USE: For fringe or marginalized
populations with novel products or services… to replace authentic user research
with actual human subjects."

Scope caveat: that paper studies LLMs as interview respondents. The "never
replace real humans" prong transfers cleanly. The "homogeneous population" prong
is about response validity and matters much less when the agent is exercising a
real app and reporting reproducible defects.

## 8 · Driver contract (SKILL.md step 0, drivers/)

**The literature supplied nothing here.** Both claims proposing a validated
abstraction — UXAgent's "universal browser connector" and its abstract verb set
— were refuted 0-3. The four verb families, the probe-at-start rule and the
three named leaks come from inspecting the live chrome-devtools-mcp and
mobile-mcp schemas on 2026-09-21. Treat them as engineering observation, not
literature support, and re-probe rather than trust the mappings.

With only two drivers inspected, three leaks may be a floor rather than a
complete list.

## Refuted — do not assert these

Voted down 0-3. Intuitive, tempting, and unsupported:

- that LLM personas are systematically sycophantic
- that synthetic evaluation cannot surface novel issues (the "circularity"
  argument from training-data patterns)
- that GPT-4o overlaps with human experts on only 21.2% of usability issues
- that detection ability is cleanly heuristic-dependent (strong on
  surface/static heuristics, weak on interaction ones)
- that UXAgent demonstrates a driver-agnostic architecture
- that LLM-simulated users systematically outperform real humans, so agent runs
  overstate usability

## Open questions

Nothing in the corpus settles these. Worth measuring once this skill has run a
few times:

1. Does the observer need a separate subagent, or does an in-context role switch
   defeat Goal-Oriented Masking? Decides whether a session costs one loop or two.
2. What is the false-positive rate for a frontier model that actually drives the
   app and must cite an artifact? Every measured rate comes from non-interactive
   conditions — this is the most valuable thing to measure.
3. How to distinguish a slow app from a broken one across drivers. The same "no
   response" carries very different weight with a wait primitive than without.
4. Which charter types actually recover the long tail. The entropy deficit is
   established; the remedy is not, nor what N personas is worth paying for.
5. Whether the capability probe stays honest as drivers are added.

## Sources

| Source | Standing |
| --- | --- |
| [UXAgent (CHI 2025 EA)](https://arxiv.org/abs/2502.12561) | primary, peer-reviewed |
| [Bach — Session-Based Test Management, STQE 2000](https://www.ida.liu.se/~TDDD04/labs/2020/exploratory_testing/stqe-sbtm.pdf) | primary, originating article |
| [GUITester (ACL 2026 Findings)](https://aclanthology.org/2026.findings-acl.946/) · [PDF](https://arxiv.org/pdf/2601.04500) | primary; only live-agent measurement; 7B driver |
| [Kuric et al. — LLMs vs real first-click data](https://arxiv.org/pdf/2605.18302) | preprint, not peer-reviewed; authors sell real-user testing; open data |
| [Guerino et al. — GPT-4o heuristic evaluation](https://arxiv.org/pdf/2506.16345) | primary; static screenshots, no interaction |
| [Salminen et al. — synthetic users (AHs 2025)](https://dl.acm.org/doi/10.1145/3745900.3746108) | primary, peer-reviewed |
| [NN/g — synthetic users](https://www.nngroup.com/articles/synthetic-users/) | primary, practitioner; paired transcripts |
| [NN/g — rating severity of usability problems](https://www.nngroup.com/articles/how-to-rate-the-severity-of-usability-problems/) | primary; the severity scale used here |
| [Synthetic heuristic evaluation](https://arxiv.org/pdf/2507.02306) | primary; the positive case |
| [PerceptUI](https://arxiv.org/pdf/2606.05697) | primary; persona qualifier |
| [AI vs human inspector FP rates](https://arxiv.org/pdf/2510.17056) | primary; corroboration |
| [chrome-devtools-mcp tool reference](https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/tool-reference.md) | primary; driver surface |
| [mobile-mcp](https://github.com/mobile-next/mobile-mcp) | primary; driver surface |

Full report, with the vote counts and the verification trail:
<https://claude.ai/artifact/Kc8pXbxVPAKYschremrFqN>
