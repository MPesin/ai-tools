# Posting and memory — GitHub mechanics

Requires `gh` authenticated for the repo. Owner/repo from
`gh repo view --json owner,name`.

## Marker comments are the memory

Every inline comment this plugin posts ends with a hidden marker:

```
<!-- pr-review:fp <fingerprint> -->
```

The review body ends with `<!-- pr-review:round <n> -->`. Nothing else is
stored anywhere. Deleting the comments deletes the memory.

## Recovering prior findings (`prior.json`)

```
gh api --paginate repos/{o}/{r}/pulls/{n}/comments \
  --jq '.[] | select(.body | test("pr-review:fp")) | {id, path, line, original_line, body, in_reply_to_id, created_at}'
gh api --paginate repos/{o}/{r}/pulls/{n}/reviews \
  --jq '.[] | select(.body | test("pr-review:round")) | {id, body, submitted_at}'
```

Thread resolution state needs GraphQL:

```
gh api graphql -f query='query($o:String!,$r:String!,$n:Int!){
  repository(owner:$o,name:$r){ pullRequest(number:$n){
    reviewThreads(first:100){ nodes{ id isResolved isOutdated
      comments(first:1){ nodes{ databaseId body path } } } } } } }' \
  -f o={o} -f r={r} -F n={n}
```

Build `prior.json` entries `{fingerprint, path, anchor, claim (the comment's
first paragraph), comment_id, thread_id, resolved, round}` — only from
comments carrying the marker; comments by humans or other bots are not
findings (address mode reads those). Round = highest `pr-review:round` seen,
else 0.

## Posting a round

Preconditions, in order:
1. The user saw the exact list (path:line, severity, first sentence of each
   comment, and which go to the body) and said yes.
2. `gh api repos/{o}/{r}/pulls/{n}/reviews --jq '.[] | select(.state=="PENDING")'`
   is empty for the current user. A pending review blocks a new one with 422;
   offer to delete it (`DELETE …/reviews/{id}`) or stop.
3. Inline targets are lines present in the head-side diff. Parse hunk headers
   in `diff.patch` (`@@ -a,b +c,d @@`: head lines `c..c+d-1`); a finding whose
   line is outside every hunk of its file, or flagged `off_diff`, goes into
   the body list instead. GitHub rejects the entire review otherwise.

One call creates and submits the review — no pending state to get stuck in:

```
gh api repos/{o}/{r}/pulls/{n}/reviews --input review.json
```

`review.json`:
```json
{
  "commit_id": "<head sha>",
  "event": "COMMENT",
  "body": "<summary block>\n\n<off-diff findings as a list with permalinks>\n\n<!-- pr-review:round 2 -->",
  "comments": [
    {"path": "src/Api/Orders.cs", "line": 57, "side": "RIGHT",
     "body": "**Important** — quantity is never validated …\n\nEvidence: …\n\n```suggestion\n…\n```\n\n<!-- pr-review:fp src/Api/Orders.cs::CreateOrder::bug::quantity -->"}
  ]
}
```

- Multi-line comments add `start_line` and `start_side: "RIGHT"`.
- One comment per unique finding; at most 25 inline, the rest in the body.
- `suggestion` blocks only when `suggestion` is non-null in the finding.
- Permalinks use the full 40-character head sha:
  `https://github.com/{o}/{r}/blob/<sha>/<path>#L57-L58`.
- On a 422, retry once with every inline comment moved into the body, and
  tell the user which lines were rejected. No second retry.
- Round 2+: body opens with the prior-round status line
  (`3 fixed · 1 open · 0 regressed`), and new nits are not posted.

## Closing fixed findings

For each prior finding the verifier marked `fixed` (thread not yet resolved):

```
gh api repos/{o}/{r}/pulls/{n}/comments/{comment_id}/replies -f body='Fixed in <sha7> — verified by pr-review.'
gh api graphql -f query='mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread{ isResolved } } }' -f id=<thread_id>
```

Only threads whose first comment carries this plugin's marker are ever
resolved. Human threads are never touched by review mode.

## Without a PR

Local ranges have no markers; the report says so and `learn` is the only
memory. Do not invent a ledger file.
