# Canterbury-Bankstown Council scraper

This is a scraper that runs on [Morph](https://morph.io). To get started [see the documentation](https://morph.io/documentation).

It scrapes development applications for [Canterbury-Bankstown Council](https://www.cbcity.nsw.gov.au/) from the council's [DA tracker](https://eplanning.cbcity.nsw.gov.au/ApplicationSearch) and feeds [PlanningAlerts](https://www.planningalerts.org.au/authorities/bankstown).

Issues with this authority are tracked in the shared issue tracker: [planningalerts-scrapers/issues#1459](https://github.com/planningalerts-scrapers/issues/issues/1459).

## How the site is structured

- The tracker lists every application lodged in a period (`yesterday`, `thisweek`, `lastweek`, `thismonth` or `lastmonth`) on one page, with no paging. It covers development applications, complying development and construction certificates, including those from private certifiers.
- Each application is an `article.application-result-card` with the reference, a `Type - description` paragraph, and `dt`/`dd` pairs for Address and Lodged.
- The page says how many applications it found. The scraper raises an error if the number of cards doesn't match.
- DAs on exhibition are only published on the NSW Planning Portal, under PAN references, so they are not scraped here.

## Running

```
bundle install
bundle exec ruby scraper.rb
```

Environment variables:

- `MORPH_AUSTRALIAN_PROXY` - optional; when set (e.g. `http://morph:password@au.proxy.oaf.org.au:8888`) all requests go through the Australian proxy.
- `MORPH_PERIOD` - optional; one of `yesterday`, `thisweek`, `lastweek`, `thismonth` or `lastmonth`. By default both `thismonth` and `lastmonth` are scraped.
- `MORPH_DEBUG` - optional; when set, prints each record as it is saved.

Expected output is a count per period followed by:

```
Finished - added N records
```

with N usually a few hundred, and a `data.sqlite` file in the working directory.
