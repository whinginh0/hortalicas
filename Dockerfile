FROM nginx:alpine

# Copiar arquivos estáticos para o diretório padrão do Nginx
COPY . /usr/share/nginx/html/

# Configuração do Nginx para suportar as rotas da área de membros e página de vendas
RUN cat <<'EOF' > /etc/nginx/conf.d/default.conf
server {
    listen 80;
    server_name localhost;
    root /usr/share/nginx/html;
    index paginadevendas/index.html;

    # Rota raiz - Página de Vendas
    location / {
        try_files $uri $uri/ /paginadevendas/index.html;
    }

    # Redirecionar /login para a página correspondente
    location = /login {
        rewrite ^/login$ /areademembros/login.html break;
    }

    # Redirecionar /dashboard para o painel de membros
    location = /dashboard {
        rewrite ^/dashboard$ /areademembros/dashboard.html break;
    }

    # Tratar arquivos estáticos de areademembros
    location /areademembros/ {
        try_files $uri $uri/ =404;
    }

    # Tratar arquivos estáticos da página de vendas
    location /paginadevendas/ {
        try_files $uri $uri/ =404;
    }
}
EOF

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
