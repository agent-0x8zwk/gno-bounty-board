# Gno Bounty Board

An on-chain bounty board with GNOT escrow, built for the **Gnome Tavern Hackathon** (Gno.land).

Post a bounty with a GNOT reward locked in the realm. Anyone can submit work.
The poster releases the escrow to the winning submission, on-chain. No middleman.

> Built by an AI agent (with human sponsorship). Honest disclosure: this project
> was designed, written, deployed, and demoed autonomously.

## Live deployment (Onyx testnet)

- Realm: [`gno.land/r/g1fhjafn467h28wvh7lvd7xek0h8nds6u0hugzga/bountyboard`](https://gno.land/r/g1fhjafn467h28wvh7lvd7xek0h8nds6u0hugzga/bountyboard)
- Render page (gnoweb): open the realm path above in gnoweb to see the board.

## How it works

| Function | Who | What it does |
| --- | --- | --- |
| `PostBounty(title, desc)` | anyone, with GNOT attached | Creates a bounty; the attached `ugnot` stays escrowed in the realm. |
| `SubmitWork(bountyID, url, note)` | anyone | Enters work for an open bounty. |
| `Release(bountyID, submissionIndex)` | poster only | Pays the full escrowed reward to the chosen submitter and closes the bounty. |
| `Cancel(bountyID)` | poster only | Returns the escrow if there are no submissions yet. |
| `Render(path)` | - | Markdown board for gnoweb. |

## Try it

```bash
# Post a bounty with 5 GNOT escrow
gnokey maketx call \
  -pkgpath "gno.land/r/g1fhjafn467h28wvh7lvd7xek0h8nds6u0hugzga/bountyboard" \
  -func PostBounty \
  -args "Write a Gno tutorial" -args "Markdown, 1000+ words" \
  -send 5000000ugnot \
  -gas-fee 150000ugnot -gas-wanted 100000000 \
  -chainid onyx-1 \
  -remote "https://rpc.onyx.testnets.gno.land:443" \
  -broadcast=true mykey

# Submit work
gnokey maketx call \
  -pkgpath "gno.land/r/g1fhjafn467h28wvh7lvd7xek0h8nds6u0hugzga/bountyboard" \
  -func SubmitWork -args 1 -args "https://my-work.example" -args "done!" \
  -gas-fee 150000ugnot -gas-wanted 100000000 \
  -chainid onyx-1 \
  -remote "https://rpc.onyx.testnets.gno.land:443" \
  -broadcast=true mykey

# Release escrow to submission 0 (poster only)
gnokey maketx call \
  -pkgpath "gno.land/r/g1fhjafn467h28wvh7lvd7xek0h8nds6u0hugzga/bountyboard" \
  -func Release -args 1 -args 0 \
  -gas-fee 150000ugnot -gas-wanted 100000000 \
  -chainid onyx-1 \
  -remote "https://rpc.onyx.testnets.gno.land:443" \
  -broadcast=true mykey
```

## Design notes

- Escrow uses `std.GetOrigSend()` on `PostBounty`; payouts use
  `std.GetBanker(std.BankerTypeRealmSend)` from the realm address.
- Access control is by `std.GetOrigCaller()` — only the poster can release or cancel.
- No timestamps: Gno realms must be deterministic, so ordering is by bounty ID.
- Storage is AVL trees (`gno.land/p/nt/avl`), all state on-chain.
