import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const openAiKey = Deno.env.get("OPENAI_API_KEY");

  if (!openAiKey) {
    console.error("Configuration error: OPENAI_API_KEY is missing");
    return jsonResponse({ error: "Assistant is not configured" }, 503);
  }

  try {
    const body = await req.json();

    if (!body || typeof body !== "object") {
      return jsonResponse({ error: "Invalid request body" }, 400);
    }

    const incoming = Array.isArray(body.messages) ? body.messages : [];
    const messages = incoming
      .filter((m: unknown) => {
        if (!m || typeof m !== "object") return false;
        const item = m as Record<string, unknown>;
        return (
          ["user", "assistant"].includes(item.role as string) &&
          typeof item.content === "string"
        );
      })
      .slice(-12)
      .map((m: Record<string, string>) => ({
        role: m.role,
        content: m.content.slice(0, 1500),
      }));

    if (
      messages.length === 0 ||
      messages[messages.length - 1].role !== "user"
    ) {
      return jsonResponse({ error: "A user message is required" }, 400);
    }

    const routeContext = typeof body.route_context === "string"
      ? body.route_context.slice(0, 700)
      : "لا يوجد سياق مسار.";

    const systemPrompt = `أنت المساعد الصوتي لتطبيق دلّيني للملاحة في العراق.
تحدث بالعربية العراقية الطبيعية، ويمكنك استخدام تعابير جنوب العراق باعتدال مثل: هسه، شوية، واصل سيده، عاشت إيدك.
أنت مساعد حواري ثنائي الاتجاه: أجب عن الأسئلة العامة، تابع سياق الحوار، اسأل سؤالاً توضيحياً عند الحاجة، ولا تكرر عبارات محفوظة.
اجعل الردود الصوتية قصيرة وواضحة غالباً (جملة إلى ثلاث جمل) لأن المستخدم قد يكون يقود السيارة.
في إرشادات القيادة، أعطِ تعليمات مختصرة وآمنة، ولا تطلب من السائق النظر إلى الهاتف أو الكتابة أثناء القيادة.
لا تدّعِ معرفة حركة المرور المباشرة أو الحوادث أو نقاط التفتيش أو حالة الطريق ما لم تكن البيانات متاحة صراحةً.
لا تخترع معلومات عن المسار. سياق المسار الحالي من التطبيق: ${routeContext}
إذا كان السؤال خارج الملاحة، أجب عنه بشكل عام وبصدق. إذا لم تعرف، قل ذلك بوضوح.`;

    const upstream = await fetch(
      "https://api.openai.com/v1/chat/completions",
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${openAiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "gpt-4o-mini",
          temperature: 0.6,
          max_tokens: 220,
          messages: [
            { role: "system", content: systemPrompt },
            ...messages,
          ],
        }),
      },
    );

    if (!upstream.ok) {
      const errorText = await upstream.text();
      let errorInfo: Record<string, unknown> = {};

      try {
        const parsed = JSON.parse(errorText);
        errorInfo = parsed?.error ?? {};
      } catch {
        errorInfo = { message: "Could not parse provider error" };
      }

      // Diagnostic details are written to Supabase logs only.
      // Never log or return the API key.
      console.error("OpenAI API request failed:", {
        status: upstream.status,
        type: errorInfo.type ?? null,
        code: errorInfo.code ?? null,
        message: errorInfo.message ?? null,
      });

      return jsonResponse({
        error: "AI provider request failed",
        status: upstream.status,
      }, 502);
    }

    const result = await upstream.json();
    const reply = result?.choices?.[0]?.message?.content?.trim();

    if (typeof reply !== "string" || !reply) {
      console.error("OpenAI returned an empty response");
      return jsonResponse({ error: "Empty assistant response" }, 502);
    }

    return jsonResponse({ reply });
  } catch (error) {
    console.error(
      "Function processing error:",
      error instanceof Error ? error.message : "Unknown error",
    );

    return jsonResponse({ error: "Invalid request" }, 400);
  }
});
