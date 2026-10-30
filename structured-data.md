# Structured metadata

Every generated page includes one `application/ld+json` script in its shared head. `ClaphamShopfronts::PageMetadata` composes [MooX::Role::JSON_LD](https://metacpan.org/pod/MooX::Role::JSON_LD) alongside the SEO role. Its `json_ld_type` and `json_ld_fields` methods define the document, and the head calls `json_ld_wrapped`.

## Mapping

| Published information | Schema.org representation | Identifier |
| --- | --- | --- |
| Project website | [WebSite](https://schema.org/WebSite), linked through each page's `isPartOf` | `<site URL>/#website` |
| Homepage | [WebPage](https://schema.org/WebPage), with the website as `mainEntity` | Homepage canonical URL plus `#webpage` |
| All photos | [CollectionPage](https://schema.org/CollectionPage) with an ordered [ItemList](https://schema.org/ItemList) as `mainEntity` | Gallery canonical URL plus `#webpage`; list uses `#photographs` |
| Unit page | WebPage whose `mainEntity` is the physical premises | Unit canonical URL plus `#webpage` |
| Enduring premises | [Place](https://schema.org/Place) with a PostalAddress | Unit canonical URL plus `#premises` |
| Published photograph | [ImageObject](https://schema.org/ImageObject), included in the gallery list and its unit page's `hasPart` | Gallery URL plus `#image-<filename hash>` |
| Public historical annotation | CreativeWork in the unit page's `hasPart` | Embedded annotation; no invented event identity |

Page URLs agree with canonical and OpenGraph URLs. The premises name and address come from the recorded street address, independently of which business was photographed. A postcode is included when recorded. No locality, country or coordinates are inferred from incomplete address data.

Photographs expose their capture date as `dateCreated`, public captions, photographed business names, published content and thumbnail URLs, and recorded attribution as [`creditText`](https://schema.org/creditText) when present. Dimensions use [QuantitativeValue](https://schema.org/QuantitativeValue) with pixel units. The latest capture is referenced through `primaryImageOfPage`; gallery list positions preserve capture-date order, including the existing ID tie-breaker.

## Shared photographs and stable identity

`Photo->image_anchor` hashes the UTF-8 managed filename with SHA-256. The gallery supplies the corresponding HTML anchor. Identity depends on the photograph's managed path, so changing the image host leaves its identifier unchanged. `contentUrl` and `thumbnailUrl` follow the current image-base configuration.

The builder gathers every published association before rendering. Each shared ImageObject therefore contains the same premises, historical names and captions on both unit pages and in the gallery. Multiple captions are retained as an array. The gallery lists the image once. Conflicting capture dates for one managed image are rejected before any output is written.

## Evidence and omissions

The metadata describes an archive, so a premises is represented as a Place without asserting that a particular LocalBusiness is currently trading there. Photograph identities come from their dated observations; later occupancy records do not relabel them.

Published historical annotations keep their existing evidence labels: `Published source` or `Reported, unconfirmed`. Their descriptions become `text`, source links become `citation`, and [`temporalCoverage`](https://schema.org/temporalCoverage) retains the supplied year, month or day. These are annotations about the premises, not declarations of exact opening or closure dates.

Internal database notes, unknown opening dates, opening hours, coordinates and current trading status are omitted. Build and import times are not published as photo creation or publication dates. The decorative image used on the homepage or an empty gallery has no inferred capture date.

## Encoding and checks

The encoder produces deterministic JSON as Perl characters; Template Toolkit writes UTF-8. HTML delimiters and Unicode line/paragraph separators are represented with JSON escapes before the role wraps the document in a script element. A caption containing `</script>`, HTML, quotes or non-ASCII text round-trips as data without terminating the script.

Rebuild with `perl bin/build-site.pl` and verify with `bin/check`. Tests cover parsing, safe embedding, URL configuration, shared images, chronology, partial dates, optional facts, empty galleries, read-only database access and regeneration of custom Result methods.
