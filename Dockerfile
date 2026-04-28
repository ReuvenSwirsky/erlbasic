FROM erlang:27 AS build

WORKDIR /app
COPY . .

RUN rebar3 as prod release \
    && cp docker/sys.config _build/prod/rel/erlbasic/releases/0.1.0/sys.config


FROM erlang:27-slim AS runtime

WORKDIR /opt/erlbasic
COPY --from=build /app/_build/prod/rel/erlbasic/ ./

RUN mkdir -p /data/erlbasic/users

EXPOSE 5555 8081
VOLUME ["/data/erlbasic/users"]

CMD ["bin/erlbasic", "foreground"]
