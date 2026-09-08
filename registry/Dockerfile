# offline-registry 通用离线依赖源服务镜像
# 服务内容（通过卷挂载数据，一套镜像服务任意多个项目）：
#   - nginx     :8081  /maven/ Maven 静态仓库、/go/ Go module proxy、/node-dist/ Node 发行包、/cargo/ Cargo 离线源
#   - Verdaccio :4873  npm 私有缓存
#
# 数据目录通过卷挂载到容器（见 docker-compose.yml / README）：
#   data/maven -> /data/maven
#   data/go    -> /data/go
#   data/node-dist -> /data/node-dist
#   data/cargo -> /data/cargo
#   data/verdaccio-storage -> /opt/verdaccio/storage
FROM node:20-alpine

RUN apk add --no-cache nginx curl \
    && npm install -g verdaccio@6 --registry=https://registry.npmmirror.com/

COPY start.sh /opt/start.sh
COPY conf/verdaccio-offline.yaml /opt/verdaccio/config.yaml
COPY conf/nginx.conf /etc/nginx/http.d/default.conf

RUN chmod +x /opt/start.sh \
    && mkdir -p /data/maven /data/go /data/cargo /data/node-dist

EXPOSE 8081 4873

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=5 \
    CMD curl -sf http://127.0.0.1:4873/ >/dev/null && curl -sf http://127.0.0.1:8081/maven/ >/dev/null || exit 1

CMD ["/opt/start.sh"]
