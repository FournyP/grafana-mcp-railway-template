FROM nginx:1.31.6-alpine

COPY ./nginx.conf.template /etc/nginx/nginx.conf.template
COPY ./path-key.conf.template /etc/nginx/path-key.conf.template
COPY ./docker-entrypoint.d/10-render-config.sh /docker-entrypoint.d/10-render-config.sh
RUN chmod +x /docker-entrypoint.d/10-render-config.sh

EXPOSE 80
