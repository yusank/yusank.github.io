ARG HUGO_DIR=.
ARG HUGO_ENV_ARG=production
FROM klakegg/hugo:0.90.1-alpine-onbuild AS hugo

FROM nginx
COPY nginx.conf /etc/nginx/conf.d/nginx.conf
COPY --from=hugo /target /usr/share/nginx/html
EXPOSE 80
EXPOSE 443