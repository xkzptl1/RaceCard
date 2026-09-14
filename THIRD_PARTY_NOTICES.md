# Third-party notices

## OpenF1

RaceCard consumes OpenF1 data. [Website](https://openf1.org/) · [Documentation](https://openf1.org/docs/) · [Upstream repository license](https://github.com/br-g/openf1/blob/main/LICENSE). The upstream repository license inspected for this pass is CC BY-NC-SA 4.0. This identifies the upstream repository license; it is not a blanket assertion that all underlying Formula 1 data or imagery can be redistributed on those terms. No OpenF1 implementation source is bundled.

OpenF1 remains subject to its own licensing and service conditions. RaceCard's license does not replace or override them. Users must comply with provider conditions. Production Live usage may require credentials, a paid tier or other provider authorization under the current service terms. Check the official documentation/provider before use.

## Swift dependencies

Detected licenses below come from the pinned package license texts. The full license/notice files are retained under Documentation/ThirdParty. These dependencies retain their own licenses; RaceCard's non-commercial restrictions do not purport to relicense them.

| Project | Pinned version/revision | Source | Detected license |
|---|---|---|---|
| mqtt-nio | 14c8e627440a751ea564d996185d9a2d8a37593b | [Source](https://github.com/swift-server-community/mqtt-nio.git) | Apache-2.0 |
| swift-algorithms | 1.2.1 | [Source](https://github.com/apple/swift-algorithms.git) | Apache-2.0 with Swift Runtime Library Exception |
| swift-asn1 | 1.7.2 | [Source](https://github.com/apple/swift-asn1.git) | Apache-2.0 |
| swift-async-algorithms | 1.1.5 | [Source](https://github.com/apple/swift-async-algorithms.git) | Apache-2.0 with Swift Runtime Library Exception |
| swift-atomics | 1.3.1 | [Source](https://github.com/apple/swift-atomics.git) | Apache-2.0 with Swift Runtime Library Exception |
| swift-certificates | 1.20.0 | [Source](https://github.com/apple/swift-certificates.git) | Apache-2.0 |
| swift-collections | 1.6.0 | [Source](https://github.com/apple/swift-collections) | Apache-2.0 with Swift Runtime Library Exception |
| swift-configuration | 1.2.0 | [Source](https://github.com/apple/swift-configuration.git) | Apache-2.0 |
| swift-crypto | 4.5.2 | [Source](https://github.com/apple/swift-crypto.git) | Apache-2.0 |
| swift-distributed-tracing | 1.4.1 | [Source](https://github.com/apple/swift-distributed-tracing.git) | Apache-2.0 |
| swift-http-structured-headers | 1.7.0 | [Source](https://github.com/apple/swift-http-structured-headers.git) | Apache-2.0 |
| swift-http-types | 1.8.0 | [Source](https://github.com/apple/swift-http-types.git) | Apache-2.0 |
| swift-log | 1.15.1 | [Source](https://github.com/apple/swift-log.git) | Apache-2.0 |
| swift-nio | 2.102.0 | [Source](https://github.com/apple/swift-nio.git) | Apache-2.0 |
| swift-nio-extras | 1.35.1 | [Source](https://github.com/apple/swift-nio-extras.git) | Apache-2.0 |
| swift-nio-http2 | 1.46.0 | [Source](https://github.com/apple/swift-nio-http2.git) | Apache-2.0 |
| swift-nio-ssl | 2.37.4 | [Source](https://github.com/apple/swift-nio-ssl.git) | Apache-2.0 |
| swift-nio-transport-services | 1.28.0 | [Source](https://github.com/apple/swift-nio-transport-services.git) | Apache-2.0 |
| swift-numerics | 1.1.1 | [Source](https://github.com/apple/swift-numerics.git) | Apache-2.0 with Swift Runtime Library Exception |
| swift-service-context | 1.3.0 | [Source](https://github.com/apple/swift-service-context.git) | Apache-2.0 |
| swift-service-lifecycle | 2.12.0 | [Source](https://github.com/swift-server/swift-service-lifecycle) | Apache-2.0 |
| swift-system | 1.8.1 | [Source](https://github.com/apple/swift-system) | Apache-2.0 with Swift Runtime Library Exception |

Additional vendored implementation notices (including cryptographic/native components where supplied upstream) are preserved under `Documentation/ThirdParty/Vendored` with their package-relative paths.

## Visuals, fonts and factual metadata

No third-party raster/vector artwork, proprietary font, source PDF or prior screenshot is bundled in the public edition. App UI uses macOS system fonts and symbols through platform APIs. Neutral team badges are text/shapes; unavailable driver images use a system avatar. Driver photos fetched at runtime stay local and remain subject to their source rights.

Factual metadata retains provenance. Exact FIA/F1 presentation shapes and associated calibrations have been excluded. See Documentation/PUBLIC_BUILD.md.

## Rights disclaimer

RaceCard is not affiliated with, endorsed by, or sponsored by Formula 1, Formula One Management, Formula One Licensing, the FIA, OpenF1, any constructor/team or driver. All trademarks, logos, images, names and other third-party materials remain the property of their respective rights holders. RaceCard's license does not grant rights to third-party data, trademarks, photographs, diagrams or other protected materials.

## Vendored native components

- llhttp (inside swift-nio): MIT; full notice in `Documentation/ThirdParty/Vendored/swift-nio/CNIOLLHTTP/LICENSE`. Source: https://github.com/nodejs/llhttp.
- BoringSSL (inside swift-nio-ssl), revision `817ab07ebb53da35afea409ab9328f578492832d`: ISC/OpenSSL and component notices; full upstream text in `Documentation/ThirdParty/Vendored/swift-nio-ssl/BoringSSL-LICENSE`. Source: https://boringssl.googlesource.com/boringssl/.
