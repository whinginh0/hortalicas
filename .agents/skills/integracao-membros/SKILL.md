---
name: integracao-membros
description: Instâncias de integração de área de membros, bancos de dados Supabase, e-mails do Brevo, e-mails transacionais de compra e webhooks de checkout.
---

# Skill de Integração da Área de Membros

Esta skill guia o agente no processo de configuração e integração de novas áreas de membros conectadas ao banco de dados Supabase, envios de e-mails transacionais com Brevo, e tratamento de webhooks de checkout da **GGCheckout** via **Supabase Edge Functions**.

---

## 1. Banco de Dados: Supabase

> [!IMPORTANT]
> O usuário **NÃO** irá criar as tabelas, colunas, RLS ou políticas manualmente. O próprio agente Antigravity, utilizando as ferramentas de MCP do Supabase (ou rodando scripts SQL via API de administrador do banco), deve criar e configurar toda a infraestrutura de banco de dados automaticamente.

### Estrutura da Tabela `usuarios`
- **Nome da Tabela**: `usuarios`
- **RLS (Row Level Security)**: Habilitado. O agente deve criar uma política de leitura pública (`Select`) anon para permitir que o formulário de login pesquise se o e-mail inserido possui acesso.
- **Colunas**:
  - `id` (int8 ou uuid): Chave primária.
  - `created_at` (timestamptz): Padrão `now()`.
  - `nome` (text): Nome completo do comprador.
  - `email` (text): E-mail do comprador (Unique e indexado em lowercase).
  - `plano` (text): Nome identificador do plano comprado (ex: `basico`, `completo`, `completo_orderbump`).
  - `status` (text): Estado da compra (ex: `approved`, `paid`, `refunded`).

---

## 2. Webhook via Supabase Edge Function (GGCheckout -> Edge Function)

A integração entre a **GGCheckout** e o **Supabase** deve ser feita através de uma **Supabase Edge Function** criada e implantada pelo agente. Esta função recebe o POST do webhook da GGCheckout, processa o plano/order bump, insere os dados no banco de dados e dispara o e-mail transacional do Brevo.

### Payload da GGCheckout (Formato de Entrada)
```json
{
  "event": "pix.paid",
  "createdAt": "2024-01-15T10:30:00Z",
  "customer": {
    "name": "Joao Silva",
    "email": "joao@email.com",
    "document": "12345678901",
    "phone": "5511999999999",
    "ip": "177.45.23.100"
  },
  "payment": {
    "id": "29cce702-5e7e-40da-93b0-aaa19acab32e",
    "method": "pix.paid",
    "paymentMethod": "pix",
    "gateway": "pagouai",
    "status": "paid",
    "amount": 97.00,
    "pixCode": "00020126580014BR.GOV.BCB.PIX..."
  },
  "product": {
    "id": "YbfsgK1Fgm0LzUsFglrn",
    "type": "main",
    "title": "Meu Produto Digital"
  },
  "products": [
    {
      "id": "YbfsgK1Fgm0LzUsFglrn",
      "type": "main",
      "title": "Meu Produto Digital"
    },
    {
      "id": "bump_abc123",
      "type": "orderbump",
      "title": "E-book Bonus",
      "price": 2700
    }
  ]
}
```

### Código da Edge Function (Deno/TypeScript)
O agente deve implementar a função (ex: `supabase/functions/gg-webhook/index.ts`) com a lógica abaixo:

```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-client-js@2"

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const BREVO_API_KEY = Deno.env.get('BREVO_API_KEY')!;

serve(async (req) => {
  try {
    const payload = await req.json();
    
    // 1. Filtrar eventos de pagamento aprovado
    const status = payload.payment?.status;
    if (status !== 'paid' && payload.event !== 'pix.paid') {
      return new Response(JSON.stringify({ message: "Ignore non-paid events" }), { status: 200 });
    }

    const customerName = payload.customer.name;
    const customerEmail = payload.customer.email.toLowerCase().trim();
    const mainProductTitle = payload.product.title;

    // 2. Detectar se comprou Order Bump na lista de produtos
    const products = payload.products || [];
    const orderBumpItem = products.find((p: any) => p.type === 'orderbump');
    
    const comprouOrderbump = !!orderBumpItem;
    const nomeOrderbump = orderBumpItem ? orderBumpItem.title : '';
    
    // Definir plano final no banco de dados
    const planoFinal = comprouOrderbump ? 'completo_orderbump' : 'completo';

    // 3. Upsert no Supabase
    const supabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { error: dbError } = await supabaseClient
      .from('usuarios')
      .upsert({
        nome: customerName,
        email: customerEmail,
        plano: planoFinal,
        status: 'paid'
      }, { onConflict: 'email' });

    if (dbError) throw dbError;

    // 4. Disparar e-mail no Brevo
    const brevoResponse = await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: {
        'api-key': BREVO_API_KEY,
        'content-type': 'application/json'
      },
      body: JSON.stringify({
        sender: { name: "[NOME_DO_SEU_PROJETO_OU_PRODUTO]", email: "[EMAIL_DE_CONTATO_E_SUPORTE]" },
        to: [{ email: customerEmail, name: customerName }],
        subject: "Seu acesso ao [NOME_DO_PRODUTO_OU_MATERIAL] foi liberado!",
        templateId: [OPCIONAL_ID_DO_TEMPLATE_SE_HOUVER], // Ou passar htmlContent diretamente
        params: {
          NOME: customerName,
          EMAIL: customerEmail,
          PLANO: comprouOrderbump ? "Plano Completo + Bônus" : "Plano Completo",
          COMPROU_ORDERBUMP: comprouOrderbump,
          NOME_ORDERBUMP: nomeOrderbump,
          LINK_MEMBROS: "[LINK_DA_SUA_AREA_DE_MEMBROS]"
        }
      })
    });

    if (!brevoResponse.ok) {
      const errText = await brevoResponse.text();
      console.error("Erro Brevo:", errText);
    }

    return new Response(JSON.stringify({ success: true }), { status: 200 });
  } catch (err) {
    console.error("Erro no processamento:", err);
    return new Response(JSON.stringify({ error: err.message }), { status: 500 });
  }
});
```

---

## 3. Configuração do E-mail de Acesso no Brevo (Sendinblue)

### Template HTML do E-mail Transacional
O template HTML enviado no campo `htmlContent` (ou cadastrado no painel do Brevo) deve seguir o seguinte layout estruturado:

```html
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; line-height: 1.6; color: #333333; margin: 0; padding: 0; }
        .wrapper { max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #e0e0e0; border-radius: 8px; }
        .header { text-align: center; margin-bottom: 24px; }
        .important-notice { background-color: [COR_AVISO_IMPORTANTE_FUNDO]; border-left: 4px solid [COR_AVISO_IMPORTANTE_BORDA]; color: [COR_AVISO_IMPORTANTE_TEXTO]; padding: 15px; border-radius: 4px; margin-bottom: 24px; font-size: 0.9rem; }
        .plan-box { background-color: [COR_CAIXA_PLANO_FUNDO]; border: 1px solid [COR_CAIXA_PLANO_BORDA]; border-radius: 6px; padding: 15px; margin-bottom: 24px; }
        .plan-title { font-weight: bold; color: [COR_CAIXA_PLANO_TEXTO]; }
        .bump-card { background: linear-gradient(135deg, [COR_CARD_BUMP_FUNDO_1], [COR_CARD_BUMP_FUNDO_2]); border: 2px dashed [COR_CARD_BUMP_BORDA]; border-radius: 8px; padding: 15px; margin-bottom: 24px; text-align: center; }
        .bump-title { font-weight: bold; color: [COR_CARD_BUMP_TEXTO]; font-size: 0.95rem; }
        .cta-button { display: inline-block; background-color: [COR_BOTAO_CTA_FUNDO]; color: [COR_BOTAO_CTA_TEXTO] !important; font-weight: bold; text-decoration: none; padding: 14px 28px; border-radius: 30px; margin: 15px 0; text-align: center; }
        .raw-link { font-size: 0.8rem; color: #757575; word-break: break-all; margin-top: 10px; }
        .footer { font-size: 0.75rem; color: #9e9e9e; text-align: center; margin-top: 30px; border-top: 1px solid #e0e0e0; padding-top: 15px; }
    </style>
</head>
<body>
    <div class="wrapper">
        <div class="header">
            <h2>Acesso Liberado! 🚀</h2>
        </div>

        <!-- AVISO IMPORTANTE: APENAS LOGIN SEM SENHA CONVENCIONAL -->
        <div class="important-notice">
            <strong>⚠️ COMO ACESSAR:</strong> O seu login é realizado inserindo apenas o seu e-mail de compra (<strong>{{params.EMAIL}}</strong>). Não é necessário criar ou utilizar nenhuma senha convencional no sistema para acessar.
        </div>

        <p>Olá, <strong>{{params.NOME}}</strong>!</p>
        <p>Parabéns pela aquisição! Seu acesso ao nosso material foi processado e já está totalmente liberado no sistema.</p>

        <!-- DETALHES DO PLANO -->
        <div class="plan-box">
            <span class="plan-title">Seu Plano Ativo:</span>
            <p style="margin: 5px 0 0 0; font-size: 1.1rem; font-weight: bold;">{{params.PLANO}}</p>
        </div>

        <!-- CARD DO ORDER BUMP CASO TENHA COMPRADO -->
        {% if params.COMPROU_ORDERBUMP %}
        <div class="bump-card">
            <span class="bump-title">🎉 Parabéns pelo Upgrade!</span>
            <p style="margin: 5px 0 0 0; font-size: 0.85rem; color: [COR_CARD_BUMP_TEXTO];">
                Identificamos que você também garantiu o produto adicional: <br>
                <strong>{{params.NOME_ORDERBUMP}}</strong>.<br>
                Ele já foi liberado e está disponível na sua área de membros!
            </p>
        </div>
        {% endif %}

        <p>Para entrar no seu painel de estudos, clique no botão abaixo e faça login inserindo o seu e-mail cadastrado:</p>

        <!-- BOTÃO DE LOGIN -->
        <div style="text-align: center;">
            <a href="{{params.LINK_MEMBROS}}" class="cta-button">ACESSAR ÁREA DE MEMBROS</a>
        </div>

        <!-- LINK COMPLETO / EXTENSO EMBAIXO -->
        <p style="margin-top: 20px; margin-bottom: 5px; font-size: 0.85rem; font-weight: bold; color: #616161;">Caso o botão acima não funcione, copie e cole o endereço abaixo no seu navegador:</p>
        <div class="raw-link">
            {{params.LINK_MEMBROS}}
        </div>

        <div class="footer">
            <p>Ambiente seguro de aprendizagem. Se precisar de ajuda, responda a este e-mail.</p>
        </div>
    </div>
</body>
</html>
```

---

## 4. Integração do Frontend (Login & Dashboard)

Ao configurar o template de frontend da área de membros:
1. No arquivo `login.html`, configure o objeto `PAGE_CONFIG` com a `supabaseUrl` e a `supabaseKey` (Anon public key) corretas do projeto.
2. O arquivo `login.html` buscará o e-mail digitado na tabela `usuarios` e redirecionará para `dashboard.html` passando os parâmetros via URL:
   `dashboard.html?email=email@email.com&name=Nome&plano=completo`
3. O `dashboard.html` salva a sessão no `localStorage` e exibe apenas os guias correspondentes ao plano do usuário.
