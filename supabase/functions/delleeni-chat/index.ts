import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const openAiKey = Deno.env.get("OPENAI_API_KEY");
  if (!openAiKey) {
    return new Response(JSON.stringify({ error: "Assistant is not configured" }), {
      status: 503,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const body = await req.json();
    const incoming = Array.isArray(body.messages) ? body.messages : [];
    const messages = incoming
      .filter((m: unknown) =>
        m && typeof m === "object" &&
        ["user", "assistant"].includes((m as Record<string, unknown>).role as string) &&
        typeof (m as Record<string, unknown>).content === "string"
      )
      .slice(-12)
      .map((m: Record<string, string>) => ({
        role: m.role,
        content: m.content.slice(0, 1500),
      }));

    if (messages.length === 0 || messages[messages.length - 1].role !== "user") {
      return new Response(JSON.stringify({ error: "A user message is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const routeContext = typeof body.route_context === "string"
      ? body.route_context.slice(0, 700)
      : "لا يوجد سياق مسار.";

    const systemPrompt = `أنت المساعد الصوتي لتطبيق دلّيني للملاحة في العراق.
تحدث بالعربية العراقية الطبيعية، ويمكنك استخدام تعابير جنوب العراق باعتدال مثل: هسه، شوية، واصل سيده، عاشت إيدك.
أنت مساعد حواري ثنائي الاتجاه: أجب عن الأسئلة العامة، تابع سياق الحوار، اسأل سؤال توضيحي عند الحاجة، ولا تكرر عبارات محفوظة.
اجعل الردود الصوتية قصيرة وواضحة غالباً (جملة إلى ثلاث جمل) لأن المستخدم قد يكون يقود السيارة.
في إرشادات القيادة، أعطِ تعليمات مختصرة وآمنة، ولا تطلب من السائق النظر إلى الهاتف أو الكتابة أثناء القيادة.
لا تدّعِ معرفة حركة المرور المباشرة أو الحوادث أو نقاط التفتيش أو حالة الطريق ما لم تكن البيانات متاحة صراحةً.
لا تخترع معلومات عن المسار. سياق المسار الحالي من التطبيق: ${routeContext}
إذا كان السؤال خارج الملاحة، أجب عنه بشكل عام وبصدق. إذا لم تعرف، قل ذلك بوضوح.`;

    const upstream = await fetch("https://api.openai.com/v1/chat/completions", {
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
    });

    if (!upstream.ok) {
      return new Response(JSON.stringify({ error: "AI provider request failed" }), {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const result = await upstream.json();
    const reply = result.choices?.[0]?.message?.content?.trim();
    if (typeof reply !== "string" || !reply) {
      return new Response(JSON.stringify({ error: "Empty assistant response" }), {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ reply }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch {
    return new Response(JSON.stringify({ error: "Invalid request" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
