// Package bountyboard is an on-chain bounty board with GNOT escrow.
//
// Anyone can post a bounty with a GNOT reward locked in the realm,
// anyone can submit work, and the poster releases the escrow to the
// winner. Open, permissionless, and rendered natively in gnoweb.
package bountyboard

import (
	"chain"
	"chain/banker"
	"chain/runtime/unsafe"
	"strconv"
	"time"

	"gno.land/p/nt/avl/v0"
)

type Bounty struct {
	ID        uint64
	Poster    address
	Title     string
	Desc      string
	Reward    chain.Coin
	Open      bool
	CreatedAt time.Time
}

type Submission struct {
	BountyID  uint64
	Submitter address
	URL       string
	Note      string
	CreatedAt time.Time
}

var (
	bounties    = avl.NewTree() // id -> Bounty
	submissions = avl.NewTree() // "bountyID:index" -> Submission
	subCount    = avl.NewTree() // bountyID -> int
	nextID      uint64
	admin       address
)

func init() {
	admin = unsafe.OriginCaller()
}

// PostBounty creates a bounty. Attach the reward as GNOT with the call;
// it stays escrowed in the realm until released or cancelled.
func PostBounty(cur realm, title, desc string) uint64 {
	send := unsafe.OriginSend()
	if len(send) != 1 || send[0].Denom != "ugnot" || send[0].Amount <= 0 {
		panic("bounty requires a ugnot payment attached to the call")
	}
	reward := send[0]
	if title == "" {
		panic("title required")
	}
	nextID++
	b := Bounty{
		ID:        nextID,
		Poster:    unsafe.OriginCaller(),
		Title:     title,
		Desc:      desc,
		Reward:    reward,
		Open:      true,
		CreatedAt: time.Now(),
	}
	bounties.Set(strconv.FormatUint(b.ID, 10), b)
	return b.ID
}

// SubmitWork enters work for an open bounty.
func SubmitWork(cur realm, bountyID uint64, url, note string) {
	b := mustBounty(bountyID)
	if !b.Open {
		panic("bounty is closed")
	}
	if url == "" {
		panic("work url required")
	}
	key := strconv.FormatUint(bountyID, 10)
	n := 0
	if subCount.Has(key) {
		n = subCount.Get(key).(int)
	}
	s := Submission{
		BountyID:  bountyID,
		Submitter: unsafe.OriginCaller(),
		URL:       url,
		Note:      note,
		CreatedAt: time.Now(),
	}
	submissions.Set(key+":"+strconv.Itoa(n), s)
	subCount.Set(key, n+1)
}

// Release pays the escrowed reward to the chosen submission. Poster only.
func Release(cur realm, bountyID uint64, submissionIndex int) {
	caller := unsafe.OriginCaller()
	b := mustBounty(bountyID)
	if caller != b.Poster {
		panic("only the poster can release the bounty")
	}
	if !b.Open {
		panic("bounty is closed")
	}
	key := strconv.FormatUint(bountyID, 10)
	sk := key + ":" + strconv.Itoa(submissionIndex)
	if !submissions.Has(sk) {
		panic("no such submission")
	}
	s := submissions.Get(sk).(Submission)

	banker_ := banker.NewBanker(banker.BankerTypeRealmSend, cur)
	banker_.SendCoins(unsafe.CurrentRealm().Address(), s.Submitter, chain.Coins{b.Reward})
	b.Open = false
	bounties.Set(key, b)
}

// Cancel returns the escrow to the poster if there are no submissions yet.
func Cancel(cur realm, bountyID uint64) {
	caller := unsafe.OriginCaller()
	b := mustBounty(bountyID)
	if caller != b.Poster {
		panic("only the poster can cancel")
	}
	if !b.Open {
		panic("bounty is closed")
	}
	key := strconv.FormatUint(bountyID, 10)
	if subCount.Has(key) && subCount.Get(key).(int) > 0 {
		panic("cannot cancel with submissions; release instead")
	}
	banker_ := banker.NewBanker(banker.BankerTypeRealmSend, cur)
	banker_.SendCoins(unsafe.CurrentRealm().Address(), b.Poster, chain.Coins{b.Reward})
	b.Open = false
	bounties.Set(key, b)
}

func mustBounty(id uint64) Bounty {
	k := strconv.FormatUint(id, 10)
	if !bounties.Has(k) {
		panic("no such bounty")
	}
	return bounties.Get(k).(Bounty)
}

// GetBounty returns a bounty by id (for off-chain reads via vm/qeval).
func GetBounty(id uint64) Bounty { return mustBounty(id) }

// GetSubmission returns submission i of bounty id (for vm/qeval).
func GetSubmission(id uint64, i int) Submission {
	k := strconv.FormatUint(id, 10) + ":" + strconv.Itoa(i)
	if !submissions.Has(k) {
		panic("no such submission")
	}
	return submissions.Get(k).(Submission)
}

// Render shows the board in gnoweb.
func Render(path string) string {
	out := "# Gno Bounty Board\n\n"
	out += "Post a bounty with GNOT escrow. Submit work. Poster releases the reward on-chain.\n\n"
	out += "---\n\n"
	for i := nextID; i >= 1; i-- {
		k := strconv.FormatUint(i, 10)
		if !bounties.Has(k) {
			continue
		}
		b := bounties.Get(k).(Bounty)
		status := "OPEN"
		if !b.Open {
			status = "CLOSED"
		}
		out += "## #" + strconv.FormatUint(i, 10) + " " + b.Title + " [" + status + "]\n\n"
		out += b.Desc + "\n\n"
		out += "- Reward: `" + b.Reward.String() + "`\n"
		out += "- Poster: `" + string(b.Poster) + "`\n"
		if subCount.Has(strconv.FormatUint(i, 10)) {
			out += "- Submissions: " + strconv.Itoa(subCount.Get(strconv.FormatUint(i, 10)).(int)) + "\n"
		}
		out += "\n"
	}
	if nextID == 0 {
		out += "_No bounties yet. Be the first to post one._\n"
	}
	return out
}
