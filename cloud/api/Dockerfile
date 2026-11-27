# Build from the repo root, so the engine package is in reach:
#   docker build -f cloud/api/Dockerfile .
FROM dart:stable AS build
WORKDIR /src
COPY packages/cricket_engine packages/cricket_engine
COPY cloud/api cloud/api
WORKDIR /src/cloud/api
RUN dart pub get
RUN dart compile exe bin/server.dart -o /server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /server /server
EXPOSE 8080
CMD ["/server"]
