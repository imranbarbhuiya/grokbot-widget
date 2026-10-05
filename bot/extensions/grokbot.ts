import cursorGrokBotAgents from "@cursor/bdk/extensions/cursor-grokbot-agents";

const name = process.env.GROKBOT_AGENT_NAME;
if (!name) throw new Error("Set GROKBOT_AGENT_NAME to the exact existing bot name.");

export default cursorGrokBotAgents({ agents: [name] });
