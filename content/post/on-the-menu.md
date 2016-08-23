{
    "title": "On Todays Menu",
    "description": "On Today's Menu, a silly menu generator",
    "date": "2015-08-02",
    "tags": [
        "Silly", "Side Project"
    ]
}

Back in my [science](http://bioinformatics.bris.ac.uk/) days we would occasionally eat lunch at the cool university canteen/study lounge place, who would kindly update the menu on their [website](http://www.bristol.ac.uk/conferences-hospitality/hospitality/cafes/studylounge.html) each week. Being a cool/lazy programmingman I wrote a quick hacky script+cron job that would download &amp; parse the menu file, then email me and my friend the food for that day. Neato!

This worked for approximately two weeks, then it broke because whoever was responsible for uploading the menu would do it late, or set the link incorrectly or randomly change format from .pdf to .doc and back again. This prompted me to think about how my menu script handled failure (not at all), and I thought instead of some boring 'GERROR: NO MENU FOUND :[' message in the email, it would be funny to use some RNG and come up with some ridiculous food instead.

So I did, and wasted the rest of the day giggling at what I'd done, so much so that I whacked it up as a website with a fancy free template I found on the internet, and shoved the whole thing up on Heroku for all to see:

## [http://menu.porkcullis.com](http://menu.porkcullis.com)

Tell your friends! Now they too can enjoy such delicacies as:

> Cauliflower gazpacho, served on milk

or 

> Beef and artisinal broccoli flatbread, served on garbage

or how about some

> Mouth-watering dog stroganov, stuffed with goose