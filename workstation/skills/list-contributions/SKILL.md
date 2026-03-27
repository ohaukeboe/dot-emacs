# Skill: List Contributions

Generate a resume-ready summary of contributions to a project by analyzing its git history.

## Usage

The user will provide a path to a git repository (or you should use the current working directory if it is a git repo). They may optionally specify:

-   **Author name or email** — to filter commits (default: infer from `git config user.name` / `git config user.email`)
-   **Date range** — e.g. "last year", "2023-2024", "since January"
-   **Focus areas** — e.g. "backend", "infrastructure", "testing"

## Procedure

1.  **Identify the author.** Run `git config user.name` and `git config user.email` in the target repo unless the user specifies an author. Confirm with the user if multiple identities appear in the log.

2.  **Extract the commit history.** Run:

    ```sh
    git log --author="<author>" --pretty=format:"%h %ad %s" --date=short --no-merges
    ```

    Apply any date range filter with `--since` / `--until` if the user specified one.

3.  **Analyze and categorize.** Read through the commits and group them into high-level themes such as:

    -   New features / product work
    -   Bug fixes and reliability improvements
    -   Performance optimizations
    -   Infrastructure / DevOps / CI-CD
    -   Refactoring / code quality
    -   Documentation
    -   Testing
    -   Security improvements
    -   Dependency management / upgrades

    Discard trivial commits (typo fixes, merge commits, version bumps) unless they form a meaningful pattern.

4.  **Synthesize resume bullet points.** For each theme with meaningful contributions, write 1-3 concise bullet points that:

    -   **Start with a strong action verb** (Designed, Implemented, Migrated, Reduced, Automated, etc.)
    -   **Quantify impact when possible** (infer from commit frequency, scope of changes, or files touched)
    -   **Describe the what and the why**, not just the how
    -   **Use professional, non-technical-jargon language** appropriate for a resume
    -   Avoid referencing specific commit hashes or internal naming

5.  **Present the results.** Output:

    -   A brief summary line (repo name, date range, total commits analyzed)
    -   The categorized bullet points, ordered by significance
    -   Optionally, a "raw themes" section listing the commit subjects grouped by category, so the user can refine

## Example Output

> **my-project** — 142 commits from 2023-01 to 2024-06
>
> -   Designed and implemented a real-time notification system, improving user engagement across the platform
> -   Migrated the CI/CD pipeline from Jenkins to GitHub Actions, reducing build times by consolidating 12 workflow configurations
> -   Improved API reliability by systematically resolving error-handling gaps across 8 service endpoints
> -   Automated database migration tooling, enabling zero-downtime schema changes in production

## Notes

-   If the repository is very large (thousands of commits), offer to narrow the date range or focus on specific paths/directories.
-   If the user has commits under multiple email addresses, combine them.
-   The user may iterate on the output — be ready to rephrase, combine, or expand bullet points.
