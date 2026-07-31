{
    "title": "Claude gave my party game the same bug that almost broke Apollo 11",
    "description": "I built a charades/heads up game you can play in your browser!",
    "date": "2026-04-10",
    "project": {
        "name": "Guessr",
        "url": "https://guessr.porkcullis.com",
        "description": "A charades/heads up style guessing game you can play in your browser.",
        "repo": "https://github.com/popeshoe/guessr",
        "icon": "📱"
    },
    "tags": [
        "Project", "Code", "AI"
    ]
}

Here's how a drunken utterance led me to strip my phone of its sense of up, confound Claude, and do battle with NASA's dreaded spectre: gimbal lock. All to make a simple heads-up style guessing game that you can try here:

## [https://guessr.porkcullis.com](https://guessr.porkcullis.com)

### Why

A while ago I was drunk in a Bristol pub with some friends and we found ourselves trying to play one of those charades style guessing games in the style of heads-up. Going through the Google Play Store we found that almost every version we tried was some combination of ugly, hard to use, severely limited, or had terrible performance. 

After a few semi-successful rounds we gave up, defeated. What stuck with me was my friend saying that these apps seem like the kind of thing that a decent LLM could shit out in a single prompt. When I got home I figured I'd give it a go. 

At the time I was lukewarm about AI writing software, it could clearly do some of the job, but all my attempts at anything adventurous had pretty bad results. The best use I'd found for it was to have it write boilerplate for me, and migrate changes I'd made in one part of the code to others, junior dev stuff. Around the same time Opus 4 was being touted on [hacker news](https://news.ycombinator.com/) as the new hot shit, capable of one-shotting anything you could ask for with a good enough prompt.

### What

So with my lightly used Github copilot subscription in one hand, and a plucky (but simple) idea in the other, I set about it. All the game screens and basic functionality worked in a single blast, perhaps not surprisingly since we're just shuffling a list of strings and recording yes/no against each one but I was surprised given my prior experience. 

By far the most time and tokens went into making the accelerometer controls work, for a long time the AI would churn away, trying to resolve a tilt up or down from the stream of `DeviceOrientationEvent`, whenever it had solved for one orientation it would break another. It eventually got to the point where it built an [orientation debugging screen](https://guessr.porkcullis.com?debug) so that it and I could look at the values in real time and I could report to Opus what axes were changing in various orientations, it still took a number of iterations to get a somewhat working solution. 

Eventually I got frustrated and looked at the [mdn docs](https://developer.mozilla.org/en-US/docs/Web/API/DeviceMotionEvent/accelerationIncludingGravity) myself, and suggested it try the `devicemotion` event listener instead of `deviceorientation` along with a link to the docs. Opus immediately solved it on that single prompt, huzzah! The issue turned out to be [gimbal lock](https://en.wikipedia.org/wiki/Gimbal_lock) and the position in which I had the player hold their phone was coincidentally exactly where the lock would occur so that even a tiny movement of the phone would feed back wildly chaotic readings.

> [!wat]
> Gimbal lock was a problem for the [Apollo program](https://en.wikipedia.org/wiki/Gimbal_lock#On_Apollo_11), this episode where I ask a computer to write basic javascript puts me in the same calibre as any of those mission control nerds.

`deviceorientation` describes the phone as three Euler angles applied in order: spin, then tilt front-to-back, then roll. Tilt it 90° and the roll axis swings around until it lines up with the spin axis, so two of the three knobs now do the same job and a huge range of values all describe the same physical orientation, that's gimbal lock. The chaotic readings weren't noise, they were all correct — the browser was picking a different but equally valid answer every few frames. `devicemotion` avoids it by never decomposing anything: `accelerationIncludingGravity` gives you which way gravity is pulling on each of the phone's axes, and one `atan2` turns that into a tilt angle that behaves everywhere.

With that solved I just had to make the thing usable, I added snazzy animations to the in-game cards, vibrations for when you got things right and wrong, as well as to alert you that time was running out. 

I had been experimenting with Cloudflare and seeing what services I get as a freeloader, and so found Cloudflare Pages an ideal place to host the static files, and it even automagically set it up to be served on my domain. Drop in a github action to build and deploy on push and it's like I'm a proper devops guy. Not bad!

### Worth?

Here's what I got with my two evenings and one month's worth of inflated copilot tokens:

- Nice UX
  - Orientation warning
  - Game event vibrations
  - Animations
  - Generally looks pretty good
  - tilty controls with button fallbacks
- Tons of categories
- PWA Manifest so you can install it to your phone

I'd say that's pretty cool, check it out for yourself (Phone recommended):

## [https://guessr.porkcullis.com](https://guessr.porkcullis.com)

### Wax

This was a learning exercise more than an attempt to make some bullet-proof app that I could sell for a billion doll hairs, in that regard it was interesting and informative. The AI did way better than I'd expected, even with the orientation issues I was surprised at how good it was at making subjective judgements like how to make the brutalist, semi unstyled first draft look nicer, or how fast and bouncy the animation should be. In the end I came away with two conclusions:

**Cost** - Inference is pricey, the two evenings I spent on this used ~90% of my Copilot allowance. This all took place in the strange few months where all the inference providers were wising up to just how expensive their loss leaders were becoming. A month or two before, my basic 10 GBP/month copilot subscription was basically unlimited, now the cost per token for Opus 4.6 went from 3x to 27x, to Microsoft flipping the table and completely changing its Copilot Pro subscription to how it is today. 

**Programming** - These models got good _fast_, 2 years ago they were cool interesting toys but flawed and annoying enough to put me off using them for anything serious. This is simply no longer true, the whole industry has changed in those two years where not embracing their weighty tendrils just means doing things the slow way. I remember early in my career writing ActionScript for a Flash embed, reading about how javascript was going to replace Flash and not quite believing that this thing we used to validate forms and load paginated content might replace such a firmly entrenched dependency, especially for rich, interactive, multimedia work (and youtube). Yet here we are in that world, with more features, better multimedia, better security, better accessibility, better everything. Nobody regrets moving away from Flash (except maybe Adobe) and we can still watch [Homestar Runner](https://homestarrunner.com/).

Will we see a similar leap in the next two years? I wouldn't be shocked if we find ourselves on an LLM plateau and start to only see small incremental steps in quality and efficiency until the next big thing is discovered. Or maybe it keeps accelerating and these models end up more like compilers, black boxes whose output it wouldn't even occur to us to check for correctness. I'm sure there are old nerds who loved hand crafting assembly language, but I seriously doubt they found themselves in a world of Pascal and C and felt worse off for it.

I saw [a great Hank Green video](https://www.youtube.com/watch?v=a6sYYrLTOjQ) where he talks about the [Jevons effect](https://en.wikipedia.org/wiki/Jevons_paradox). He speculates whether the demand for software is finite, or whether there will always and forever be more software that people want writing, I hope for my own sake it's that one, because ya boy needs that [pepsi max money](https://i.ibb.co/cSXTxFxg/noice.jpg).
