{
    "title": "Style guide",
    "description": "Internal reference for every styled element. Draft - never published.",
    "date": "2026-07-31",
    "draft": true
}

A draft page exercising every element the stylesheet handles, so the styles can be
reviewed in both colour schemes without hunting for a real post that happens to use
them. Never published — `buildDrafts` is false, so this only renders with `hugo -D`.

## Headings

Heading levels below, to check the top-margin scale descends properly.

### Third level

Body copy for reference. The measure should land around 66 characters at the desktop
size, and links like [this one](/about) carry the growing-underline effect that fills
on hover. **Bold text** and `inline code` sit inline with it.

#### Fourth level

Short paragraph under a fourth-level heading.

## Alert callouts

None of the real posts use these, so this is the only place they can be reviewed.

> [!NOTE]
> Useful information that a reader should know even when skimming.

> [!TIP]
> Optional advice for doing something better.

> [!IMPORTANT]
> Key information a reader needs to achieve their goal.

> [!WARNING]
> Urgent info needing immediate attention to avoid a problem.

> [!CAUTION]
> Advises about risks or negative outcomes of an action.

> [!WAT]
> The bespoke one. Not part of GitHub's set.

## Quotes

A plain blockquote, which the render hook wraps in a `<figure>`:

> Ed impotently shook his fist at the flying robot, immediately embarrassed that his
> newly nanocrafted gloves had cracked and were flaking off his hands, adding to the
> detritus on the floor.

## Lists

* Unordered item one
* Unordered item two, long enough to wrap onto a second line so the hanging indent
  and line-height can be checked against surrounding body copy
* Unordered item three

1. Ordered item one
2. Ordered item two
3. Ordered item three

## Code

Inline `const x = 1` inside a sentence, then a block:

```js
function colourForEpoch(epoch) {
  var round = Math.floor(epoch / COLOURS.length);
  var pos = epoch % COLOURS.length;
  return correctedPermutationForRound(round)[pos];
}
```

## Table

| Token | Light | Dark |
|---|---|---|
| `--surface` | `#fff` | `#14161a` |
| `--text` | `#515151` | `#c8ccd2` |
| `--border` | `#e5e5e5` | `#2c3038` |

## Rule

Below is an `<hr>`, which should be a single line rather than a doubled bevel.

---

And some text after it.
