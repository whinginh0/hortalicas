FROM nginx:alpine

# Copiar arquivos estáticos para o diretório padrão do Nginx
COPY . /usr/share/nginx/html/

# Configuração personalizada do Nginx para suportar as rotas amigáveis da área de membros e da página de vendas
RUN echo ' \
server { \
    listen 80; \
    server_name localhost; \
    root /usr/share/nginx/html; \
    index paginadevendas/index.html; \
    \
    # Rota raiz - Página de Vendas \
    location / { \
        try_files $uri $uri/ /paginadevendas/index.html; \
    } \
    \
    # Redirecionar /login para a página correspondente \
    location = /login { \
        try_files /areademembros/login.html$is_args$args =404; \
    } \
    \
    # Redirecionar /dashboard para o painel de membros \
    location = /dashboard { \
        try_files /areademembros/dashboard.html$is_args$args =404; \
    } \
    \
    # Tratar arquivos estáticos de areademembros \
    location /areademembros/ { \
        try_files $uri $uri/ =404; \
    } \
    \
    # Tratar arquivos estáticos da página de vendas \
    location /paginadevendas/ { \
        try_files $uri $uri/ =404; \
    } \
}' > /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
