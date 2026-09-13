import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const bridgeUrl = process.env.XAOS_BRIDGE_URL?.replace(/\/$/, "");
const bridgeToken = process.env.XAOS_BRIDGE_TOKEN;
const runtimeGeneration = process.env.XAOS_RUNTIME_GENERATION;

async function invoke(tool: string, args: Record<string, string>, signal?: AbortSignal) {
  if (!bridgeUrl || !bridgeToken || !runtimeGeneration) {
    return {
      content: [{ type: "text" as const, text: "XAOS Android bridge is not configured." }],
      details: { code: "BRIDGE_NOT_CONFIGURED" },
      isError: true,
    };
  }

  const requestId = `pi_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
  try {
    const response = await fetch(`${bridgeUrl}/tool`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${bridgeToken}`,
      },
      body: JSON.stringify({
        requestId,
        runtimeGeneration,
        tool,
        args,
        deadlineMs: 30_000,
      }),
      signal,
    });
    const payload = await response.json() as {
      status?: string;
      result?: Record<string, string>;
      error?: { code?: string; message?: string } | null;
      backend?: string | null;
      sideEffectState?: string;
    };
    const ok = response.ok && payload.status === "SUCCEEDED";
    const text = ok
      ? JSON.stringify(payload.result ?? {})
      : `${payload.error?.code ?? payload.status ?? response.status}: ${payload.error?.message ?? "tool failed"}`;
    return {
      content: [{ type: "text" as const, text }],
      details: payload,
      ...(ok ? {} : { isError: true }),
    };
  } catch (error) {
    if (signal?.aborted) throw error;
    return {
      content: [{ type: "text" as const, text: `XAOS bridge request failed: ${error instanceof Error ? error.message : String(error)}` }],
      details: { code: "BRIDGE_REQUEST_FAILED" },
      isError: true,
    };
  }
}

const ACTIVE_TOOLS = [
  "android_get_battery",
  "android_device_info",
  "android_open_app",
  "android_open_url",
];

export default function xaosExtension(pi: ExtensionAPI) {
  pi.registerTool({
    name: "android_get_battery",
    label: "Battery",
    description: "Read the Android device battery percentage and charging state.",
    promptSnippet: "Read Android battery status",
    promptGuidelines: ["Use android_get_battery when the user asks about battery level or charging state."],
    parameters: Type.Object({}),
    async execute(_id, _params, signal) {
      return invoke("android.get_battery", {}, signal);
    },
  });

  pi.registerTool({
    name: "android_device_info",
    label: "Device info",
    description: "Read Android device model, manufacturer, OS version, and SDK level.",
    promptSnippet: "Read Android device information",
    promptGuidelines: ["Use android_device_info when the user asks about this phone or Android version."],
    parameters: Type.Object({}),
    async execute(_id, _params, signal) {
      return invoke("android.device_info", {}, signal);
    },
  });

  pi.registerTool({
    name: "android_open_app",
    label: "Open app",
    description: "Open an Android application by package name. This may require user approval.",
    promptSnippet: "Open an Android app",
    promptGuidelines: ["Use android_open_app only when the user asks to open an app."],
    parameters: Type.Object({
      package: Type.String({ description: "Android package name, for example com.android.settings" }),
    }),
    async execute(_id, params, signal) {
      return invoke("android.open_app", { package: params.package }, signal);
    },
  });

  pi.registerTool({
    name: "android_open_url",
    label: "Open URL",
    description: "Open an http/https URL using an Android handler. This may require user approval.",
    promptSnippet: "Open a URL on Android",
    promptGuidelines: ["Use android_open_url only when the user asks to open a web link."],
    parameters: Type.Object({
      url: Type.String({ description: "Absolute http or https URL" }),
    }),
    async execute(_id, params, signal) {
      return invoke("android.open_url", { url: params.url }, signal);
    },
  });

  pi.on("session_start", async () => {
    // XAOS is a phone agent. Disable Pi's built-in filesystem/bash tools in this
    // runtime so provider credentials and the private Linux filesystem are not
    // exposed to the model as general-purpose tools.
    pi.setActiveTools(ACTIVE_TOOLS);
  });
}
