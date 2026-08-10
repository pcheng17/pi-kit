import { uuidv7 } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, join } from "node:path";

const VaultArtifacts = join(homedir(), "dev", "vault", "Artifacts");
const StateDir = join(homedir(), ".pi", "agent", "state", "save-context");
const NothingNotable = "(nothing notable)";
const SummaryTimeoutMs = 120_000;
const MaxToolResultChars = 2_000;

type JsonObject = Record<string, unknown>;

function isObject(value: unknown): value is JsonObject {
	return typeof value === "object" && value !== null;
}

function truncate(value: string, limit = MaxToolResultChars): string {
	if (value.length <= limit) return value;
	return `${value.slice(0, limit)}\n[... ${value.length - limit} characters truncated]`;
}

function formatContent(content: unknown, truncateText = false): string {
	if (typeof content === "string") return truncateText ? truncate(content) : content;
	if (!Array.isArray(content)) return "";

	const parts: string[] = [];
	for (const block of content) {
		if (!isObject(block) || typeof block.type !== "string") continue;

		switch (block.type) {
			case "text":
				if (typeof block.text === "string") {
					parts.push(truncateText ? truncate(block.text) : block.text);
				}
				break;
			case "thinking":
				if (typeof block.thinking === "string") {
					parts.push(`[Thinking]: ${block.thinking}`);
				}
				break;
			case "toolCall":
				if (typeof block.name === "string") {
					parts.push(`[Tool call]: ${block.name}(${JSON.stringify(block.arguments ?? {})})`);
				}
				break;
			case "image":
				parts.push("[Image attachment omitted]");
				break;
		}
	}
	return parts.join("\n");
}

function formatEntry(line: string): string {
	let entry: unknown;
	try {
		entry = JSON.parse(line);
	} catch {
		return "";
	}
	if (!isObject(entry) || typeof entry.type !== "string") return "";

	if (entry.type === "message" && isObject(entry.message)) {
		const message = entry.message;
		const role = typeof message.role === "string" ? message.role : "message";
		const text = formatContent(message.content, role === "toolResult");
		if (role === "bashExecution") {
			const command = typeof message.command === "string" ? message.command : "";
			const output = typeof message.output === "string" ? truncate(message.output) : "";
			return `[Bash]: ${command}\n${output}`.trim();
		}
		return text ? `[${role}]: ${text}` : "";
	}

	if (entry.type === "compaction" && typeof entry.summary === "string") {
		return `[Compaction summary]: ${entry.summary}`;
	}
	if (entry.type === "branch_summary" && typeof entry.summary === "string") {
		return `[Branch summary]: ${entry.summary}`;
	}
	if (entry.type === "custom_message") {
		const text = formatContent(entry.content);
		return text ? `[Extension message]: ${text}` : "";
	}
	return "";
}

async function readOffset(path: string): Promise<number> {
	try {
		const value = Number.parseInt((await readFile(path, "utf8")).trim(), 10);
		return Number.isSafeInteger(value) && value >= 0 ? value : 0;
	} catch {
		return 0;
	}
}

async function writeOffset(path: string, offset: number): Promise<void> {
	const temporaryPath = `${path}.${process.pid}.tmp`;
	await writeFile(temporaryPath, `${offset}\n`, "utf8");
	await rename(temporaryPath, path);
}

async function repoName(pi: ExtensionAPI, cwd: string): Promise<string> {
	const result = await pi.exec("git", ["-C", cwd, "rev-parse", "--show-toplevel"]);
	if (result.code !== 0 || !result.stdout.trim()) return "misc";
	return basename(result.stdout.trim());
}

function summaryPrompt(transcript: string): string {
	return [
		"Below is new content from a Pi coding-agent session.",
		"Write a concise Markdown summary with no wrapper commentary and no headings above h3.",
		"Cover key context established, decisions made and why, and learnings or gotchas discovered.",
		"Skip anything trivial or purely mechanical.",
		`If there is nothing substantive, respond with exactly: ${NothingNotable}`,
		"",
		"<session-content>",
		transcript,
		"</session-content>",
	].join("\n");
}

function responseText(response: { content: Array<{ type: string; text?: string }> }): string {
	return response.content
		.filter((block) => block.type === "text" && typeof block.text === "string")
		.map((block) => block.text as string)
		.join("\n")
		.trim();
}

export default function saveContext(pi: ExtensionAPI) {
	let pending = Promise.resolve();

	const checkpoint = async (eventName: string, trigger: string, ctx: ExtensionContext, parentSignal?: AbortSignal) => {
		const sessionFile = ctx.sessionManager.getSessionFile();
		const model = ctx.model;
		if (!sessionFile || !model || !ctx.modelRegistry.hasConfiguredAuth(model)) return;

		try {
			await mkdir(StateDir, { recursive: true });

			const sessionId = ctx.sessionManager.getSessionId();
			const offsetPath = join(StateDir, `${sessionId}.offset`);
			const lastOffset = await readOffset(offsetPath);
			const file = await readFile(sessionFile, "utf8");
			const lines = file.split("\n");
			if (lines.at(-1) === "") lines.pop();
			if (lines.length <= lastOffset) return;

			const transcript = lines
				.slice(lastOffset)
				.map(formatEntry)
				.filter(Boolean)
				.join("\n\n");

			if (!transcript.trim()) {
				await writeOffset(offsetPath, lines.length);
				return;
			}

			const timeout = AbortSignal.timeout(SummaryTimeoutMs);
			const signal = parentSignal ? AbortSignal.any([parentSignal, timeout]) : timeout;
			const response = await ctx.modelRegistry.complete(
				model,
				{
					messages: [
						{
							role: "user",
							content: [{ type: "text", text: summaryPrompt(transcript) }],
							timestamp: Date.now(),
						},
					],
				},
				{
					maxTokens: 2_048,
					signal,
					cacheRetention: "none",
					sessionId: uuidv7(),
				},
			);
			const summary = responseText(response);
			if (!summary) return;

			if (summary !== NothingNotable) {
				const targetDir = join(VaultArtifacts, await repoName(pi, ctx.cwd));
				await mkdir(targetDir, { recursive: true });
				const targetFile = join(targetDir, `${sessionId}.md`);
				const timestamp = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
				const section = `## ${timestamp} — ${eventName} (${trigger})\n\n${summary}\n\n`;
				await writeFile(targetFile, section, { encoding: "utf8", flag: "a" });
			}

			await writeOffset(offsetPath, lines.length);
		} catch (error) {
			if (ctx.hasUI) {
				const message = error instanceof Error ? error.message : String(error);
				ctx.ui.notify(`save-context failed: ${message}`, "warning");
			}
		}
	};

	const enqueue = (eventName: string, trigger: string, ctx: ExtensionContext, signal?: AbortSignal) => {
		pending = pending.then(() => checkpoint(eventName, trigger, ctx, signal));
		return pending;
	};

	pi.on("session_before_compact", (event, ctx) =>
		enqueue("session_before_compact", event.reason, ctx, event.signal),
	);
	pi.on("session_shutdown", (event, ctx) => enqueue("session_shutdown", event.reason, ctx));
}
