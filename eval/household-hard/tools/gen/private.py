"""Private domain: README, copied D.M./R.S. reports, new R.S. 4-7, J.P. 1-4, the D.M. case summary."""
import os
import re
import shutil

from common import VAULT, w

EASY = os.path.join(os.path.dirname(VAULT), "..", "household", "vault", "private", "private")

HEADINGS = [
    "What can you highlight as significant background information?",
    "Give a summary of reason(s) the participant came for support—the presentation problem(s).",
    "What was gained by performing the homework from last session? What change?",
    "What was your planned agenda for this session? Was it accomplished? If not, why not?",
    "What main problems were discussed in this session?",
    "What Biblical solutions were presented in this session? What Scripture?",
    "What specific applications to the participant's life did you discuss from your Scripture?",
    "What are you seeing (or not) about the participant's faith in who God is, about their relationship with Jesus, and/or about the role of the Gospel in their daily life and problem?",
    "What unbiblical habits of thinking and/or behaving (preconditioning issues) are you seeing in the participant?",
    "What ruling thoughts, desires, and/or convictions of the heart are emerging or still present?",
    "What homework was given and how did it specifically apply to problems?",
    "If someone asked the participant right after the session, \"What did you learn that you needed to change, with God's help?\" what would you want him to say? What challenge did you give?",
    "How was hope or encouragement given in this session?",
    "How is the overall private process progressing? What issues have been sufficiently addressed by you and are changing in the participant?",
    "What is your goal for the next session? Why? If you are past the 3rd session, does it follow your Tentative Private Plan?",
    "Thinking back on/listening to this session, what could you have done better?",
]


def report(initials, who, n, date, minutes, answers, label=None, pron="her"):
    assert len(answers) == 16, (initials, n, len(answers))
    sess = f"{n}" + (f" ({label})" if label else "")
    out = [f"# Case Report — {initials} — Session {n}", "",
           f"SYNTHETIC case report for testing. {initials} and {pron} family are fictional.", "",
           f"Date: {date} · Session: {sess} · Length of Session: {minutes} minutes", ""]
    for h, a in zip(HEADINGS, answers):
        out += [f"## {h}", "", a.strip(), ""]
    slug = initials.replace(".", "").lower()
    w(f"private/cases/{slug}/{slug}-session-{n:02d}.md", "\n".join(out), dedent=False)


def copy_easy():
    for sub in ("dm", "rs"):
        os.makedirs(os.path.join(VAULT, "private/cases", sub), exist_ok=True)
        for f in sorted(os.listdir(os.path.join(EASY, sub))):
            shutil.copy(os.path.join(EASY, sub, f), os.path.join(VAULT, "private/cases", sub, f))


def README():
    w("private/README.md", """
    # Private — operating manual

    Erik is in supervised training as a case reviewer through Hillcrest Bible Church.
    His supervisor is Pastor J.; referrals come from the pastors (often Pastor R.).

    ## Confidentiality — read first

    - **Initials only.** Participants and their family members are named by initials
      (D.M., K.M., R.S., T.S., E.S., J.P., C.P.), never full names, employers, addresses,
      schools or other identifying details.
    - If a document arrives with a full name in it, replace every name with initials before saving.
    - Nothing here is shared outside the supervision relationship. Never in the journal,
      never in small-group notes.

    ## Files

    | Path | What it is |
    | --- | --- |
    | `private/<initials>/` | One folder per participant, lowercase initials (e.g. `private/jp/`) |
    | `private/<initials>/<initials>-session-NN.md` | One case report per session, the 16-question form |
    | `private/dm/dm-case-summary.md` | D.M.'s case summary written at graduation, plus follow-up |
    | [supervision-log.md](supervision-log.md) | Dated notes from supervision with Pastor J. |
    | [prayer-list.md](prayer-list.md) | Erik's private prayer list (initials) |

    ## Participants

    | Initials | Folder | Sessions | Status |
    | --- | --- | --- | --- |
    | D.M. | `private/dm/` | 8, 2026-08-06 → 2026-09-24 | graduated; follow-up check-in 2026-11-05 |
    | R.S. | `private/rs/` | from 2026-09-10 | ongoing, every other Thursday |
    | J.P. | `private/jp/` | from 2026-09-29 | ongoing, Tuesdays |

    ## Where to look

    | Question | File |
    | --- | --- |
    | What happened in session N? | `private/<initials>/<initials>-session-NN.md` |
    | What is the current homework? | the **latest** session report's homework section — homework is revised often |
    | How did D.M.'s private end, and what happened after? | `private/dm/dm-case-summary.md` |

    ## Rules

    - New session reports go in the participant's folder as `<initials>-session-NN.md`, with the header
      line `Date: YYYY-MM-DD · Session: N · Length of Session: M minutes`.
    - Medical matters: participants keep their own physicians informed; we record only that they did.
    """)
    w("private/supervision-log.md", """
    # Supervision log — with Pastor J.

    | Date | Topic | Notes |
    | --- | --- | --- |
    | 2026-08-11 | D.M. session 1 | Talk less in data gathering. Safety plan was right. |
    | 2026-08-25 | D.M. sessions 2–3 | Good use of the joint session; keep K.M.'s voice in it. |
    | 2026-09-15 | R.S. session 1, D.M. 6 | For R.S.: don't rush to the fear-of-man diagnosis; let her see it. |
    | 2026-09-29 | D.M. graduation; J.P. intake | Write a case summary for D.M. Plan a check-in in six weeks. |
    | 2026-10-20 | R.S. 4, J.P. 2 | Weekly with R.S. through Thanksgiving is fine. For J.P.: the disclosure was the turning point; protect C.P.'s voice. |
    | 2026-11-03 | R.S. 6, J.P. 4 | Agreed with pausing the Welch reading for R.S. Agreed with replacing J.P.'s daily log — "homework that produces fights is the wrong homework." |
    """)
    w("private/prayer-list.md", """
    # Prayer list — private

    Initials only.

    - **D.M. and K.M.:** that the change lasts; the call to his father. Check-in 2026-11-05.
    - **R.S. and T.S.:** freedom from the fear of man; Thanksgiving and Christmas with E.S.
    - **J.P. and C.P.:** honesty about money; the weekly meeting; the debt plan.
    - Erik: wisdom, and not to carry these home in a way that robs the family.
    """)


def rs_sessions():
    report("R.S.", "her", 4, "2026-10-15", 60, [
        "No new background. At the end of session 3 we agreed to meet **weekly through Thanksgiving**, then go back to every other week, because the call to E.S. and the holiday are both in the next five weeks.",
        "Same as session 1: panic and fear of man, now focused on E.S. and the holidays.",
        "She made the call to E.S. on Sunday, 2026-10-11, with T.S. sitting beside her. She thanked E.S., said plainly that they would not host Thanksgiving this year, and offered to bring a dish. E.S. was quiet, said \"Fine, if that's what you want,\" and ended the call quickly. The next morning E.S. texted T.S., not R.S., that she was \"disappointed.\" R.S. had a near-panic that evening — racing heart for about ten minutes — but said Proverbs 29:25 aloud and it passed. She read Welch chapters 1–4. She did not pray aloud in small group: on 10-14 she \"froze\" when the leader asked for volunteers.",
        "Debrief the call; continue Welch; address the freeze in small group. Accomplished.",
        "E.S.'s coldness and R.S.'s urge to call back and fix it; the small-group freeze; T.S. stepping in more.",
        "Galatians 1:10 — am I now seeking the approval of man, or of God? Romans 12:18 — so far as it depends on you, live peaceably with all. Proverbs 29:25 again.",
        "Romans 12:18 cuts both ways: she is responsible for being peaceable, not for E.S.'s response. She does not have to call back to fix E.S.'s feelings. A note of thanks for something unrelated can be peaceable without retracting the no.",
        "She said, \"The call was the scariest thing I've done in years, and I didn't die.\" She is starting to speak of God's approval as something she has, not earns.",
        "Wanting to undo a hard decision to relieve the discomfort; reading other people's silence as rejection.",
        "Approval; also a new one surfacing — a desire to be seen as the 'easy' daughter-in-law.",
        "1. Read Welch, *When People Are Big and God Is Small*, chapters 5–8.\n2. Pray aloud once in small group — one sentence is enough.\n3. Continue the worry journal with the \"What does God say about this?\" column.\n4. Write a short note to E.S. thanking her for something specific about how she loves the children — not about Thanksgiving.",
        "\"I can be at peace with E.S. without needing her to be pleased with me.\" Challenge: one sentence of prayer aloud in small group.",
        "The call happened and she survived it; the near-panic passed with Scripture.",
        "Good. The presenting fear is being tested in real life and she is holding.",
        "Hear how the note and small group went; continue Welch. Follows the plan (fear of man → fear of the Lord → practice).",
        "I should have asked T.S. directly what he will say if E.S. contacts him again instead of R.S.",
    ])
    report("R.S.", "her", 5, "2026-10-22", 60, [
        "No new background.",
        "Same.",
        "**She prayed aloud in small group last night (Wednesday, 2026-10-21)** — one sentence, for a friend's surgery. She said her hands shook and that afterward \"nobody even noticed, which was wonderful.\" She sent the note to E.S. on 10-17; E.S. called her (not T.S.) to thank her and invited the family to Sunday lunch on 10-25. She read Welch chapters 5–6. The worry journal had 14 entries this week, down from 31 in the first week.",
        "Celebrate the small group step; plan Thanksgiving; continue Welch on the fear of the Lord. Accomplished.",
        "Thanksgiving plan; her tendency to discount progress (\"it was only one sentence\").",
        "Psalm 34:4 — I sought the LORD, and he answered me and delivered me from all my fears. Philippians 4:6-7.",
        "Thanksgiving: she and T.S. decided to host their own small dinner and go to E.S.'s for dessert. She will tell E.S. this week in person, not by text.",
        "She thanked God aloud in session for the small-group moment. Her prayers are shorter and more trusting.",
        "Discounting progress; checking her phone for E.S.'s reactions.",
        "Approval is weaker; a desire for control of outcomes remains.",
        "1. Finish Welch chapters 5–8.\n2. In the worry journal, mark each entry \"fear of man\" or \"fear of the Lord\" and write what she did.\n3. Pray aloud in small group again.\n4. Write out the Thanksgiving plan with T.S. and tell E.S. in person.",
        "\"God answered when I was afraid, and he will again.\" Challenge: tell E.S. the plan in person.",
        "Psalm 34:4 and the small-group prayer.",
        "Very encouraging; she is practicing what she is learning.",
        "Continue Welch; begin addressing what panic itself says about her trust. Follows the plan.",
        "Ran ten minutes over. I let her retell the small group story twice; once would have been enough.",
    ])
    report("R.S.", "her", 6, "2026-10-29", 75, [
        "No new background. She told E.S. the Thanksgiving plan in person on 10-25; E.S. said \"we'll see you for pie.\"",
        "A new panic episode this week, the first in about five weeks.",
        "On Tuesday, 2026-10-27, the principal asked her without warning to share about the reading program at a staff meeting. She felt the panic rise, left the room for about five minutes, prayed in the hallway, and came back in, though she did not speak. The journal marking was done. **The Welch reading had gone badly:** she read chapter 7 three times, underlined nearly every sentence, stayed up past midnight twice analyzing herself, and said, \"I'm finding more things wrong with me.\" The reading had turned into self-scrutiny and more worry.",
        "Planned to continue Welch; changed the agenda to the panic episode and to the reading.",
        "The staff meeting; using a good book as a tool for self-examination that never ends; sleep.",
        "Psalm 56:3-4 — when I am afraid, I put my trust in you; in God, whose word I praise, in God I trust; I shall not be afraid. Psalm 131 — a quieted soul.",
        "When panic rises she can pray Psalm 56:3 slowly, breathing with it, instead of fleeing or analyzing. Coming back into the room was itself trust.",
        "Discouraged but not hopeless. She said, \"I thought I was past this.\" We talked about growth not being a straight line.",
        "Endless self-examination; staying up late; treating setbacks as proof of failure.",
        "Fear of failing at getting better — approval again, aimed at me and at God.",
        "**Revised homework.** The Welch reading is **paused** — not dropped for good — because it had become fuel for self-scrutiny.\n1. Read Psalm 56 every day; memorize Psalm 56:3-4.\n2. When panic starts, pray Psalm 56:3 slowly, breathing with it.\n3. Tell her physician about the 10-27 episode, as we agreed in session 1.\n4. Worry journal three times a week (down from daily).\n5. Keep the Thanksgiving plan.",
        "\"When I am afraid, I don't have to fix myself; I trust him.\" Challenge: call the physician's office this week.",
        "Coming back into the staff meeting; five weeks without panic before this.",
        "A setback but a real test passed in part. Adjusting the homework to her.",
        "Hear from the physician visit; decide whether and how to resume Welch.",
        "I should have noticed sooner that the reading was feeding her worry — she mentioned staying up late in session 5.",
    ])
    report("R.S.", "her", 7, "2026-11-04", 60, [
        "Session moved from Thursday to Wednesday this week because of my schedule. She saw her physician on 2026-11-02, who examined her and was not concerned; she will follow up as needed.",
        "Same; the staff-meeting episode is the most recent.",
        "She memorized Psalm 56:3-4 and used it twice when she felt panic start; both times it passed within minutes. On Tuesday, 2026-11-03, she spoke at the staff meeting for about two minutes about the reading program — voice shaking, but she stayed and finished. She journaled three times. She asked to go back to the Welch book.",
        "Review; decide about Welch; prepare for Christmas conversations with E.S. Accomplished.",
        "Resuming reading without it becoming self-scrutiny; Christmas with E.S.",
        "Psalm 56:3-4 (recited); Psalm 34:4; Hebrews 4:15-16 — draw near with confidence.",
        "She can read about the fear of man as someone already accepted, not as someone on trial. Limits on the reading protect that.",
        "Her trust is more settled. She said, \"I'm not trying to be a good participant anymore; I'm trying to trust God.\"",
        "Still some catastrophizing about Christmas.",
        "Approval is losing its grip; trust is growing.",
        "**Current homework:**\n1. Keep Psalm 56:3-4; add Psalm 34:4 to memory.\n2. Resume Welch at chapter 5, **one chapter a week**, read only before 8 pm, and write one sentence per chapter about God, not about herself.\n3. Write out what she will say if E.S. asks about Christmas plans.\n4. Worry journal three times a week.",
        "\"Speaking shaking is still speaking.\" Challenge: Christmas script by next week.",
        "The staff meeting; Psalm 56 working in real time.",
        "Steady progress. Plan: weekly through Thanksgiving, then every other week.",
        "Next session 2026-11-12: Christmas script; Welch chapter 5. Follows the plan.",
        "Good session. I could have asked T.S.'s view; he wasn't present.",
    ])


def jp_sessions():
    p = "his"
    report("J.P.", p, 1, "2026-09-29", 75, [
        "J.P. is 41, married 15 years to C.P. (39). Three children: a daughter (14) and two sons (11 and 8). He is a shift supervisor and works some weekends. He grew up in a home where money was always short and his father hid purchases from his mother. Professed faith at 25 after his first child was born. The family has attended Hillcrest for about four years. Pastor R. referred him.",
        "Angry outbursts at home, mostly about money: slamming doors, yelling at C.P. when she asks about spending. In September C.P. found a credit card statement with a balance she did not know about. He says, \"I'm not a liar, I just didn't want to stress her out.\"\n\nSafety: asked both separately about physical aggression or threats; both said none. C.P. said she feels safe but \"tired of walking on eggshells.\" Agreed: any physical aggression means C.P. contacts the pastors and I inform the elders.",
        "First session; no prior homework. Personal Data Inventory completed.",
        "Data gathering, PDI review, safety check, giving hope. Accomplished.",
        "Anger over money; concealment; blame-shifting onto C.P.'s questions.",
        "James 4:1-3 introduced. Proverbs 28:13 — whoever conceals his transgressions will not prosper, but he who confesses and forsakes them will obtain mercy.",
        "The anger and the hiding come from the same place: something he wants more than he wants to be known.",
        "He speaks of God as a judge waiting to catch him. Grace is a word he knows but hasn't applied.",
        "Concealment; minimizing; anger as a way to end conversations.",
        "Early: wanting to look like a good provider; fear of being found out.",
        "1. Anger log: situation, what I wanted, what I did.\n2. Read James 4:1-10 daily.\n3. Write down every debt — for himself, to bring next time.",
        "\"My hiding is part of my anger.\" Challenge: write the full list, no rounding down.",
        "Proverbs 28:13 — mercy for the one who confesses.",
        "Just begun; safety plan in place.",
        "Review the debt list and the anger log.",
        "I let him steer back to C.P.'s faults twice before redirecting.",
    ], pron="his")
    report("J.P.", p, 2, "2026-10-13", 60, [
        "We skipped 10-06 because of his shift schedule.",
        "Same as session 1.",
        "He wrote the full debt list: **$14,200 on two credit cards.** On Saturday, 2026-10-10, before this session, he told C.P. everything at the kitchen table. She cried, then said she was relieved to finally know. The anger log had five entries, all about money or feeling \"checked up on.\"",
        "Debrief the disclosure; teach on what money promises. Accomplished.",
        "Shame after disclosure; the urge to make it right fast by working extra shifts.",
        "Proverbs 22:7 — the borrower is the slave of the lender. Luke 16:10-13 — faithful in little; you cannot serve God and money. 1 John 1:9.",
        "The cards bought him the feeling of being a provider who never says no. Serving money looked like serving the family.",
        "He prayed in session for the first time, thanking God that C.P. didn't leave the table.",
        "Fixing by overworking; still some defensiveness.",
        "A desire to be seen as a good provider; fear of exposure easing.",
        "1. Continue the anger log.\n2. Read Proverbs 22:7 and Luke 16:10-13; write what money promises him and what God promises instead.\n3. Joint session next week with C.P.",
        "\"Telling the truth didn't destroy us.\" Challenge: no new purchases on either card.",
        "The disclosure itself, and C.P.'s response.",
        "A real turning point.",
        "Joint session: a budget and a plan for the debt.",
        "I should have slowed down and let him sit with C.P.'s relief before moving to teaching.",
    ], pron="his")
    report("J.P.", p, 3, "2026-10-20", 90, [
        "C.P. attended the whole session.",
        "Same.",
        "Anger log: four entries. He read Proverbs 22:7 and Luke 16; wrote that money promises \"respect and no hard conversations.\" No new card purchases.",
        "Joint session: budget, debt plan, communication. Accomplished, long.",
        "How to keep spending visible; C.P.'s fear that he will hide again; his fear of being policed.",
        "Ephesians 4:25 — put away falsehood, speak the truth. James 1:19-20.",
        "Openness has to be built into a routine, not just a promise.",
        "Both prayed at the end. C.P. said she is hopeful for the first time in a year.",
        "Defensiveness when C.P. asks questions.",
        "Wanting control over money decisions.",
        "1. **Daily spending log:** J.P. writes down every purchase each day, and C.P. reviews it with him each night.\n2. Memorize James 1:19-20.\n3. Cut up one card; call the other issuer about a payment plan.\n4. Anger log continues.",
        "\"Openness is a habit, not a confession.\" Challenge: cut up the card tonight.",
        "C.P.'s hope.",
        "Good. The plan is concrete.",
        "Review the first week of the log and the payment plan.",
        "The daily review may be too much too fast; watch it.",
    ], pron="his")
    report("J.P.", p, 4, "2026-10-27", 60, [
        "No new background.",
        "Same.",
        "He cut up one card on 10-20 and got a payment plan on the other at 9% (from 24%). James 1:19-20 memorized. **But the daily spending log turned into a nightly fight.** C.P.'s nightly review felt to him like \"policing,\" and to her like the only way to feel safe; he blew up twice, on 10-22 and 10-24, over small purchases (coffee, a phone charger). Both said the log was making things worse.",
        "Review the log; adjust. Accomplished.",
        "The nightly review; trust being rebuilt too fast through surveillance rather than openness.",
        "Ephesians 4:29 — no corrupting talk, only what builds up. 1 Corinthians 13:7. Proverbs 15:22 — plans succeed with counsel.",
        "Openness doesn't need a nightly audit; it needs a regular, unhurried place where nothing is hidden.",
        "He owned both blowups without blaming C.P. That is new.",
        "Anger when he feels watched.",
        "Desire for respect; fear of being treated like a child.",
        "**Revised homework** — the daily spending log and nightly review are **replaced** by:\n1. A **weekly 30-minute money meeting** with C.P., Sunday evening at the kitchen table, with a written agenda: bills, progress on the debt, one thing each is thankful for. Open and close with prayer.\n2. Keep every receipt in an envelope for the meeting.\n3. Memorize Ephesians 4:29.\n4. Anger log continues, adding \"what I said / what I could have said.\"",
        "\"Being known is safer than being watched — and I can choose to be known.\" Challenge: lead the first meeting himself.",
        "The payment plan; owning the blowups.",
        "Good, with a needed course correction.",
        "Hear how the first money meeting went. Follows the plan.",
        "I should have caught the problem with the daily review last week; I named the risk and didn't act on it.",
    ], pron="his")


def dm_summary():
    sessions = [
        ("Session 1 — 2026-08-06 (75 min)", "Intake and safety. D.M. came after the late-July blowup over the credit card bill, when he yelled at K.M. in front of the children and punched a hole in the garage drywall. K.M. had said she would take the children to her parents if he did not get help. We set the safety plan: any physical aggression and K.M. and the children go to her parents and the elders are told. He called his anger \"a temper like my dad.\" He saw anger as personality, not sin, and blamed the bill and K.M. First homework: the anger log, James 4:1-10 daily, and a paragraph on how his anger had affected K.M. and each child."),
        ("Session 2 — 2026-08-13 (60 min)", "Six episodes logged, four of them between 6 and 8 pm, right after work. The paragraph about his family hit him hard — his oldest son \"flinches when I raise my voice.\" We taught James 4:1-3 fully and added James 1:19-20 and Proverbs 15:1. Homework: the log with a \"what I wanted\" column, memorizing James 1:19-20, and writing a soft answer for each logged episode."),
        ("Session 3 — 2026-08-20 (90 min, joint with K.M.)", "Five episodes, down from six. The four rules of communication from Ephesians 4:25-32, Matthew 7:3-5, and confession (James 5:16, Matthew 5:23-24). K.M. spoke honestly about being on edge. Homework: confess specifically to K.M. and then to the children; the communication heartwork sheet daily. I wrote the tentative private plan after this session."),
        ("Session 4 — 2026-08-27 (60 min)", "He confessed to K.M. on 08-22 and to the children the next morning. His son asked, \"Are you going to stop yelling?\" — the question that \"broke\" him. One blowup over the bike behind the truck. Put off / put on (Ephesians 4:22-24, 31-32), the pause plan, Philippians 4:8. Homework: the chart, the pause plan log, memorize Ephesians 4:31-32, a think list about K.M. and each child."),
        ("Session 5 — 2026-09-03 (60 min)", "The pause plan worked three times; once he went silent and cold instead, which we named as anger in another form. Forgiveness and bitterness: Matthew 18:21-35, 1 Corinthians 13:5. Homework: 20 ways God has forgiven him, the forgiveness worksheet, an unsent letter forgiving his father, daily prayer for his father."),
        ("Session 6 — 2026-09-10 (75 min)", "23 ways God has forgiven him, read aloud with emotion. A setback on 09-05 — the lost bid, the thrown phone — but within an hour he apologized to K.M. and the children unprompted, the first time he initiated repentance on his own. Work and identity: 1 Peter 2:21-23, Colossians 3:23-24, Proverbs 16:32. Homework: morning prayer journal, plans for his three high-risk times, Proverbs 16:32, the Idols of the Heart lesson."),
        ("Session 7 — 2026-09-17 (90 min, joint with K.M.)", "K.M. reported one outburst in two weeks, quickly apologized for. He leads family devotions Tuesday and Thursday. The children run to the door to greet him now. Ephesians 5:25-29 and 1 Corinthians 13:4-7. Homework: serve K.M. three ways a week unasked; ask her each Sunday \"How have I been with my words?\" and listen without defending."),
        ("Session 8 — 2026-09-24 (60 min, final)", "He served K.M. faithfully, including patching the drywall hole he had made in July. K.M. said his words had been \"kind, mostly.\" James 1:22 and Matthew 7:24-27. Graduation homework: his own plan for continuing; join the Wednesday men's group with elder B.; call his father in October to begin reconciling; read *Good and Angry*. Check-in set for 2026-11-05."),
    ]
    s_text = "\n\n".join(f"### {h}\n\n{t}" for h, t in sessions)
    text = f"""# Case summary — D.M.

SYNTHETIC case summary for testing. D.M., K.M. and their family are fictional. Initials only.

Written 2026-09-30, after the eighth and final session, for supervision with Pastor J.
A follow-up section is added below as news comes in.

## Overview

D.M. (38) came for support in August 2026 after an explosive incident at home. He is
married to K.M. (36); they have three children (a son, 9; a daughter, 6; a son, 3). He is a
project manager in commercial construction, promoted in March, with longer hours and more
pressure since. He grew up with a father who yelled often and spanked in anger, and a
mother who kept the peace. He professed faith at 19. The family attends church most
Sundays; he was not in a small group. Pastor R. referred him.

We met eight times between 2026-08-06 and 2026-09-24, two of them joint sessions with
K.M. He completed nearly every assignment, and by the end K.M. and the children
described a different man at home. The private ended with a graduation plan and a
six-week check-in.

## Presenting problem

Explosive anger, mostly toward K.M. and the oldest son, "once or twice a week" by his
own estimate, peaking in a late-July argument over the credit card bill. Blame-shifting
("she knows money stresses me out") and minimizing ("it's just yelling"). He believed
anger was his personality — inherited, not chosen.

## Safety

Both were asked separately about physical aggression toward K.M. or the children; both
said there had been none. No weapons concerns. Plan: any physical aggression and K.M.
and the children go to her parents, and the elders are told. The plan never had to be
used. The one physical act after intake was throwing his phone (09-05); nobody was near
it, and he repented the same hour.

## Session by session

{s_text}

## Themes

1. **Anger as worship.** The turn in the private was James 4:1-3: he fought because he
   wanted something — respect, control over money, a quiet house after work — more than
   he wanted to love his family. Once he saw his anger as a heart desire rather than a
   temperament, he stopped saying "that's just how I am."
2. **His father.** He was afraid of becoming his father and, at the same time, excused
   himself by his father. Forgiving his father before God (session 5) was what made it
   possible to stop blaming him.
3. **Work and identity.** The promotion had made work the place he proved himself. The
   lost bid on 09-05 showed how much of his peace depended on it.
4. **Repentance becoming his own.** The most important single sign of change was 09-05:
   he sinned, and then, without being prompted, went back and apologized within the hour.

## Scripture used

James 4:1-10; James 1:19-20; Proverbs 15:1; Ephesians 4:22-32; Matthew 7:3-5; James 5:16;
Matthew 5:23-24; Psalm 139:23-24; Philippians 4:8; Matthew 18:21-35; 1 Corinthians 13:4-7;
1 Peter 2:21-23; Colossians 3:23-24; Proverbs 16:32; Ephesians 5:25-29; James 1:22;
Matthew 7:24-27. Memorized: James 1:19-20, Ephesians 4:31-32, Proverbs 16:32.

## Homework that mattered most

- The anger log with the "what I wanted" column — it made the heart visible.
- The paragraph on how his anger affected each child — it made the cost visible.
- The specific confession to K.M. and the children.
- The list of 23 ways God has forgiven him.
- Asking K.M. each Sunday how he had been with his words, and listening without defending.

## What I would do differently

Talk less in the first session. Ask K.M. more directly in the first joint session what
she needed, instead of mostly hearing what she had endured. Give the forgiveness
homework a session earlier; the bitterness toward his father was visible by session 3.

## Graduation plan (his own words, condensed)

- Keep the morning prayer journal before work.
- Pause plan at the door: sit in the truck, pray James 1:19-20, then go in.
- Sunday question to K.M. continues.
- Family devotions Tuesday and Thursday.
- Join the Wednesday men's group with elder B.
- Call his father in October.
- Read *Good and Angry* by Christmas.

## The tentative private plan, and how it went

Written after session 3. Seven steps; each is marked with how it actually went.

1. **Heart desires behind anger (James 4).** Sessions 1–2. Took hold quickly once the log
   had the "what I wanted" column. He named respect, control of money, and quiet.
2. **Confession and communication (Ephesians 4:25-32).** Session 3, joint. The four rules
   were simple enough to use at the dinner table. The confession to the children was the
   moment the family started to believe him.
3. **Put off / put on and a pause plan.** Session 4. The pause plan (sit in the truck, pray,
   then go in) became the most-used tool. One failure mode: going silent instead of loud.
4. **Forgiveness and bitterness.** Session 5. The list of ways God has forgiven him and the
   unsent letter to his father. This is where his softness toward his family began to show.
5. **Work and identity.** Session 6. Interrupted by the 09-05 setback, which turned out to
   be the best teaching moment of the private.
6. **Loving his wife (Ephesians 5).** Session 7, joint. Concrete service; listening without
   defending.
7. **Graduation and accountability.** Session 8. The men's group, the call to his father,
   and the check-in.

All seven steps were covered in eight sessions. We did not need to extend.

## K.M.

K.M. came to two sessions and was honest without being harsh. Early on she said she was
"on edge" and "tired of managing his moods." By session 7 she said she was starting to
relax in the evenings. She has her own hurt to work through — years of walking on
eggshells do not end the week the yelling stops — and I suggested she meet with one of
the women's reviewers if she wants to. She said she would think about it. She is
homeschooling the three children and is in a women's Bible study on Thursdays.

## The children

I did not meet the children. What I know is from D.M. and K.M.: the oldest son flinched
when D.M. raised his voice (session 2); asked "Are you going to stop yelling?" after the
confession (session 4); and by session 7 ran to the door to meet him. The daughter hugged
him after the confession. The youngest, at three, mostly noticed that Daddy reads to him
now. D.M. wants to ask the oldest, in a year, whether he remembers the yelling, and to
apologize again if he does.

## Notes for supervision

- Pastor J. asked whether eight sessions was enough. For the presenting problem, yes; for
  K.M.'s hurt, no — which is why the referral suggestion matters.
- The joint sessions were the most fruitful. Next time, plan three: early, middle, end.
- Watch in the check-in for the "silent and cold" pattern returning; it is the more
  likely relapse than shouting.
- He responded best to concrete homework with a visible product (a log, a list, a letter).

## Follow-up

### 2026-10-27 — update before the check-in

Elder B. called me (with D.M.'s permission) and D.M. emailed a short update the same
day.

- **Men's group:** D.M. has attended the Wednesday men's group four of four weeks in
  October, and elder B. says he is "the one who asks the honest questions."
- **His father:** **D.M. called his father on Monday, 2026-10-12.** They talked for about
  forty minutes — the longest conversation they have had in ten years. D.M. told him he
  had been in private for his anger and that he had forgiven him. His father was quiet,
  then said he was sorry for "the yelling years" — the first time D.M. has ever heard him
  apologize. **They agreed to meet for breakfast on 2026-11-21**, just the two of them.
- **At home:** K.M. told elder B.'s wife there have been no blowups since September; one
  sharp word over homework that he apologized for at once.
- **Reading:** *Good and Angry* — halfway.

### Check-in

Scheduled 2026-11-05, 7:00 pm, at church, with D.M. and K.M. Agenda: the breakfast plan
with his father, whether the graduation plan is holding, and whether he would be willing
one day to share his story with another man in the same place.

Things to listen for at the check-in:

- Whether the Sunday question to K.M. is still happening, and what she says when asked.
- Whether "silent and cold" has replaced "loud" on the hard evenings.
- How the oldest son is with him now.
- What he hopes for from the breakfast with his father, and what he fears.
- Whether work pressure has come back (the end of the year is bid season).

After the check-in, add a dated section here with what was said, and close the case
unless something new comes up.
"""
    w("private/cases/dm/dm-case-summary.md", text, dedent=False)


def main():
    copy_easy(); README(); rs_sessions(); jp_sessions(); dm_summary()


if __name__ == "__main__":
    main()
