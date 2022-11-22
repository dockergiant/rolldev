FROM nginx

ADD docker-entrypoint /docker-entrypoint
ADD index.html.template /usr/share/nginx/html/index.html.template
ADD img/Dnsmasq_icon.svg /usr/share/nginx/html/img/Dnsmasq_icon.svg
ADD img/portainer.png /usr/share/nginx/html/img/portainer.png
ADD img/mailhog.png /usr/share/nginx/html/img/mailhog.png

ENTRYPOINT [ "/docker-entrypoint" ]
