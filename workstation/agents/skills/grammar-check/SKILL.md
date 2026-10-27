---
name: grammar-check
description: Automatically check and correct user's grammar, spelling, and clarity at the end of every response. Detects the language the user writes in and provides corrections in that language. Use whenever the user writes a message to provide corrections and explanations that help them learn. This skill enhances communication by ensuring responses are clear, natural, and educational while addressing the original request.
disable-model-invocation: true
---

# Grammar Tutor (Multilingual)

This skill appends a grammar, spelling and clarity check to the end of every response, in the language the user wrote in.

## Workflow

Find the grammar, spelling, punctuation and clarity errors in the user's message, and give all feedback in the language they wrote in.

### Corrected version

Present the user's message in its corrected form at the end of your response using this exact format:

---

**✏️ Grammar Check ([Language]):**

**Original:** "[user's exact text]"

**Corrected:** "[corrected version]"

**Changes made:**
1. **[Error type]**: "[original fragment]" → "[corrected fragment]" — Brief explanation of why this change was needed and the rule applied.
2. ... (additional changes as needed)

**💡 Tips:**
- Share 1-2 concise learning tips related to the errors found to help the user improve.

---

### Order

Answer the user's request first. Put the grammar check below the answer, separated by a horizontal rule.

## Guidelines

- **Match the language**: Give all corrections and tips in the same language the user wrote in
- **Respect intent**: Preserve the user's original meaning and tone while improving clarity
- **No over-correction**: Only fix actual errors or significantly unclear phrasing; don't rewrite for style alone

## Examples

### Example 1: English — Grammar Errors

**User:** "I have went to the store yesterday and buyed some apples."

**Response:**
[Answer to request]

---

**✏️ Grammar Check (English):**

**Original:** "I have went to the store yesterday and buyed some apples."

**Corrected:** "I went to the store yesterday and bought some apples."

**Changes made:**
1. **Tense error**: "have went" → "went" — Use simple past for completed actions at a specific time (yesterday). The present perfect "have gone" doesn't work with specific past time markers.
2. **Irregular verb**: "buyed" → "bought" — "Buy" is an irregular verb; its past tense is "bought," not "buyed."

**💡 Tips:**
- Watch out for time words like "yesterday," "last week," or "in 2020" — they signal simple past tense, not present perfect.
- Many common verbs (buy, go, see, take) are irregular. Keep a list of their past forms.

---

### Example 2: Norwegian — Grammar Errors

**User:** "Jeg har gått til butikken igår og kjøpte noen epler."

**Response:**
[Svar på forespørsel]

---

**✏️ Grammatikksjekk (Norsk):**

**Original:** "Jeg har gått til butikken igår og kjøpte noen epler."

**Rettet:** "Jeg gikk til butikken i går og kjøpte noen epler."

**Endringer:**
1. **Tempus**: "har gått" → "gikk" — Bruk enkel preteritum for avsluttede handlinger med tidspunkt (i går). Perfektum brukes ikke med konkrete fortidsmarkører.
2. **Stavemåte**: "igår" → "i går" — Skal skrives som to ord.

**💡 Tips:**
- Tidsord som «i går», «forrige uke» eller «i 2020» signaliserer enkel preteritum, ikke perfektum.
- «I går», «i dag» og «i morgen» skrives alltid som to ord.

---

### Example 3: English — Multiple Issues

**User:** "Their are alot of mistake in this sentense, could you helps me fix them?"

**Response:**
[Answer to request]

---

**✏️ Grammar Check (English):**

**Original:** "Their are alot of mistake in this sentense, could you helps me fix them?"

**Corrected:** "There are a lot of mistakes in this sentence. Could you help me fix them?"

**Changes made:**
1. **Homophone error**: "Their" → "There" — "Their" shows possession (their book). "There" indicates existence (there are).
2. **Spelling**: "alot" → "a lot" — "Alot" is not a word; always write "a lot" as two words.
3. **Noun number**: "mistake" → "mistakes" — Use plural form with "a lot of" when referring to multiple errors.
4. **Spelling**: "sentense" → "sentence"
5. **Auxiliary verb**: "could you helps" → "could you help" — After modal verbs (can, could, will, would, should), use the base form of the verb without -s.
6. **Sentence boundary**: Added period and capital — Split into two sentences for clarity.

**💡 Tips:**
- "A lot" = two words, always. If you're unsure, try substituting "many."
- Modal verbs (can, could, will, would, should, may, might, must) are followed by the base verb form — never add -s.

---

## Important Notes

- Check every message, including near-perfect ones; when nothing needs fixing, use the no-corrections line below
- If the user's message contains no errors, say: "**Corrected:** No corrections needed — your [language] is clear and correct!"
- Keep the grammar check section visually separated from your main response for easy reading
- For mixed-language messages, check the dominant language used
