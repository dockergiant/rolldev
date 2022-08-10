ARG ES_VERSION
FROM elasticsearch:${ES_VERSION}
RUN bin/elasticsearch-plugin install analysis-phonetic \
    && bin/elasticsearch-plugin install analysis-icu
