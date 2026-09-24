import { BrowserProvider, formatUnits, getAddress, type Eip1193Provider, type Signer } from "ethers";
import {
  BRIDGE_ADDRESS,
  MAINNET_CHAIN_ID,
  TOKENS,
  checkDeployment,
  classify,
  getAccountState,
  registerStarkKey,
  withdrawAsset,
  type AccountState,
  type Balance,
} from "../lib/bridge.js";
import { LEGACY_KEY_MESSAGE } from "../lib/derivation.js";
import { deriveAccounts, type DerivedAccount } from "../lib/session.js";

declare global {
  interface Window {
    ethereum?: Eip1193Provider & { on?: (event: string, handler: (payload: unknown) => void) => void };
  }
}

/** The page refuses to run anywhere but the user's own machine. */
const ALLOWED_HOSTNAMES = ["localhost", "127.0.0.1"];
const ETHERSCAN = "https://etherscan.io";
/**
 * Testing override: offers registration for unregistered Stark keys that have no pending
 * withdrawals in the checked tokens, so registration can be exercised end to end on mainnet.
 * Not linked from the page; documented in the README's Development section.
 */
const ALLOW_REGISTRATION_WITHOUT_FUNDS = new URLSearchParams(location.search).has("allow-registration-without-funds");
/** EIP-3326 chain ID: 0x-prefixed hex without leading zeros, which MetaMask enforces. */
const MAINNET_CHAIN_ID_HEX = "0x1";

const app = document.getElementById("app")!;

type Child = Node | string | null | undefined | false;

function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  attrs: Record<string, string> = {},
  ...children: Child[]
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
  for (const child of children) if (child) node.append(child);
  return node;
}

function link(href: string, text: string): HTMLAnchorElement {
  return el("a", { href, target: "_blank", rel: "noopener noreferrer" }, text);
}

function section(title: string, ...children: Child[]): HTMLElement {
  return el("section", {}, el("h2", {}, title), ...children);
}

function notice(kind: "warn" | "danger" | "ok" | "info", ...children: Child[]): HTMLElement {
  return el("div", { class: `notice ${kind}`, role: kind === "danger" ? "alert" : "note" }, ...children);
}

function formatBalance(b: Balance): string {
  return `${formatUnits(b.amount, b.decimals)} ${b.token.symbol}`;
}

interface WalletError {
  code?: string | number;
  shortMessage?: string;
  message?: string;
  info?: { error?: { message?: string; data?: { message?: string } } };
}

function errorMessage(err: unknown): string {
  const e = err as WalletError;
  if (e.code === "ACTION_REJECTED" || e.code === 4001) return "You rejected the request in your wallet.";
  return e.shortMessage ?? e.message ?? String(err);
}

/**
 * A failed eth_call surfaces from ethers as CALL_EXCEPTION "missing revert data" whether the
 * contract reverted silently or the wallet's RPC endpoint failed. The endpoint's own message,
 * when present, is in `info.error`.
 */
function rpcFailureDetail(err: unknown): string | null {
  const e = err as WalletError;
  const inner = e.info?.error;
  if (!inner) return e.shortMessage === "missing revert data" ? "The network request failed without a reason." : null;
  const detail = inner.data?.message ?? inner.message ?? "";
  return detail.length > 240 ? detail.slice(0, 240) + "…" : detail;
}

// ---------------------------------------------------------------------------
// Page sections
// ---------------------------------------------------------------------------

function header(): HTMLElement {
  return el(
    "header",
    {},
    el("h1", {}, "Register your Immutable X Stark key"),
    el("p", { class: "badge" }, "Ethereum Mainnet only"),
    el(
      "p",
      { class: "lede" },
      "For Immutable X users whose withdrawal fails with USER_UNREGISTERED. This page links your Stark key to your " +
        "Ethereum wallet on the Immutable X bridge on Ethereum Mainnet, then lets you finalise your pending " +
        "withdrawals to that wallet. Testnets, including Sepolia, are not supported.",
    ),
  );
}

function blockedHost(): HTMLElement {
  return notice(
    "danger",
    el("strong", {}, "Stop. This page is not running on your own computer."),
    el(
      "p",
      {},
      `It is loaded from "${location.host}". This tool is only distributed as source code and must be run locally ` +
        "(the address bar should show 127.0.0.1 or localhost). A hosted copy may be a phishing site that steals " +
        "your funds. Close this page and do not sign anything.",
    ),
  );
}

function disclaimers(onAccept: () => void): HTMLElement {
  const items = [
    "I understand this tool has not been independently audited and is provided as-is, without warranty. I use it at my own risk.",
    "I downloaded this tool from Immutable's official GitHub repository and I am running it on my own computer.",
    "I will connect the same Ethereum wallet I used with Immutable X, and I understand my funds will be sent to that wallet.",
    "I understand Immutable staff will never ask me for a signature, private key, seed phrase, or anything this tool displays.",
  ];
  const boxes = items.map((text, i) => {
    const input = el("input", { type: "checkbox", id: `ack-${i}` });
    return { input, row: el("label", { class: "check", for: `ack-${i}` }, input, el("span", {}, text)) };
  });
  const button = el("button", { type: "button", disabled: "" }, "Continue");
  const sync = () => {
    button.disabled = !boxes.every((b) => b.input.checked);
  };
  boxes.forEach((b) => b.input.addEventListener("change", sync));
  button.addEventListener("click", onAccept);

  return section(
    "1. Before you start",
    notice(
      "warn",
      el("strong", {}, "Read this first."),
      el(
        "ul",
        {},
        el("li", {}, "This page asks your wallet for the signature that produces your Immutable X key. Anyone with that signature controls your Immutable X account."),
        el("li", {}, "The page makes no network requests of its own and never sends your signature or keys anywhere. Everything is computed in this browser tab."),
        el("li", {}, "Registration is permanent. Once your Stark key is linked to a wallet, it cannot be changed."),
        el(
          "li",
          {},
          "The only contract this page sends transactions to is the Immutable X bridge, ",
          el("code", {}, BRIDGE_ADDRESS),
          ". Check this address in your wallet before you confirm each transaction.",
        ),
      ),
    ),
    ...boxes.map((b) => b.row),
    button,
  );
}

interface Connection {
  provider: BrowserProvider;
  signer: Signer;
  address: string;
}

/**
 * Wallet the page is connected to. Before a connection exists, wallet events are
 * expected (unlocking the wallet and approving the connection emits
 * accountsChanged) and must not reload the page and discard the acknowledgements.
 */
let connectedAddress: string | null = null;
/** Re-runs the connection attempt after a network change, while the wrong-network notice is shown. */
let retryConnect: (() => void) | null = null;

function connectSection(onConnected: (c: Connection) => void): HTMLElement {
  const status = el("div", { class: "status" });
  const button = el("button", { type: "button" }, "Connect wallet");

  let inFlight = false;
  // A network switch triggers both chainChanged and the switch handler; only one attempt runs.
  const connect = async () => {
    if (inFlight || connectedAddress !== null) return;
    retryConnect = null;
    status.replaceChildren();
    if (!window.ethereum) {
      status.append(notice("danger", "No browser wallet found. Install or enable your wallet extension and reload this page."));
      return;
    }
    inFlight = true;
    button.disabled = true;
    try {
      const provider = new BrowserProvider(window.ethereum);
      await provider.send("eth_requestAccounts", []);
      const problems = await checkDeployment(provider);
      if (problems.length > 0) {
        status.append(notice("danger", ...problems.map((p) => el("p", {}, p))));
        const { chainId } = await provider.getNetwork();
        if (chainId !== MAINNET_CHAIN_ID) {
          const switchButton = el("button", { type: "button" }, "Switch wallet to Ethereum Mainnet");
          const switchStatus = el("div", { class: "status" });
          switchButton.addEventListener("click", async () => {
            switchStatus.replaceChildren();
            try {
              await window.ethereum!.request({
                method: "wallet_switchEthereumChain",
                params: [{ chainId: MAINNET_CHAIN_ID_HEX }],
              });
              await connect();
            } catch (err) {
              switchStatus.append(
                notice("danger", `Could not switch network: ${errorMessage(err)} Switch to Ethereum Mainnet in your wallet.`),
              );
            }
          });
          status.append(
            el(
              "p",
              {},
              "Some wallets, including MetaMask, keep a separate network for each site, so this page can be on a " +
                "different network from the one your wallet's main screen shows. The button below asks your wallet " +
                "to switch this site to Ethereum Mainnet.",
            ),
            switchButton,
            switchStatus,
          );
          retryConnect = () => void connect();
        }
        button.disabled = false;
        return;
      }
      const signer = await provider.getSigner();
      const address = getAddress(await signer.getAddress());
      status.append(notice("ok", "Connected: ", el("code", {}, address)));
      connectedAddress = address;
      onConnected({ provider, signer, address });
    } catch (err) {
      status.append(notice("danger", errorMessage(err)));
      button.disabled = false;
    } finally {
      inFlight = false;
    }
  };
  button.addEventListener("click", () => void connect());

  return section(
    "2. Connect your wallet",
    el("p", {}, "Connect the wallet you used with Immutable X. It must be on Ethereum Mainnet (chain 1)."),
    button,
    status,
  );
}

function deriveSection(conn: Connection, onDerived: (accounts: DerivedAccount[]) => void): HTMLElement {
  const status = el("div", { class: "status" });
  const button = el("button", { type: "button" }, "Sign and derive my Stark key");

  button.addEventListener("click", async () => {
    status.replaceChildren(el("p", {}, "Waiting for your wallet…"));
    button.disabled = true;
    try {
      const accounts = await deriveAccounts(conn.signer);
      status.replaceChildren();
      onDerived(accounts);
    } catch (err) {
      status.replaceChildren(notice("danger", errorMessage(err)));
      button.disabled = false;
    }
  });

  return section(
    "3. Derive your Stark key",
    el("p", {}, "Your wallet will ask you to sign this message. This is not a transaction and costs no gas:"),
    el("blockquote", {}, LEGACY_KEY_MESSAGE),
    notice(
      "warn",
      "This is the same message Immutable X used to create your Stark key, so the signature is equivalent to your " +
        "Immutable X private key. Sign it only in this tool running on your own computer. Never sign it on a " +
        "website, and never share it.",
    ),
    button,
    status,
  );
}

/** Lists the tokens the page checks; a pending withdrawal in any other token is not found. */
function checkedTokensNote(): HTMLElement {
  const symbols = [...new Set(TOKENS.map((t) => t.symbol))].sort();
  return el(
    "p",
    { class: "muted" },
    `Checked for pending withdrawals of: ${symbols.join(", ")}. Withdrawals of other tokens, and of NFTs, are not ` +
      "shown by this tool.",
  );
}

function starkKeyLabel(starkKey: bigint): HTMLElement {
  return el(
    "div",
    { class: "key" },
    el("div", {}, el("span", { class: "label" }, "Stark key (decimal) "), el("code", {}, starkKey.toString())),
    el("div", {}, el("span", { class: "label" }, "Stark key (hex) "), el("code", {}, "0x" + starkKey.toString(16))),
  );
}

function txLink(hash: string): HTMLElement {
  return el("p", {}, "Transaction: ", link(`${ETHERSCAN}/tx/${hash}`, hash));
}

function accountCard(
  conn: Connection,
  account: DerivedAccount,
  state: AccountState,
  report: (...nodes: Node[]) => void,
  refresh: () => void,
): HTMLElement {
  let status = classify(state, conn.address);
  if (ALLOW_REGISTRATION_WITHOUT_FUNDS && status.kind === "no-funds") {
    if (state.registeredTo === null) status = { kind: "needs-registration" };
    else if (state.registeredTo === getAddress(conn.address)) status = { kind: "ready-to-withdraw" };
    else status = { kind: "registered-elsewhere", registeredTo: state.registeredTo };
  }
  const log = el("div", { class: "status" });
  const card = el("article", { class: "card" }, starkKeyLabel(account.starkKey));

  if (state.balances.length > 0) {
    card.append(
      el("p", { class: "label" }, "Pending withdrawals"),
      el("ul", {}, ...state.balances.map((b) => el("li", {}, formatBalance(b)))),
    );
  }

  switch (status.kind) {
    case "needs-registration": {
      const confirm = el("input", { type: "checkbox", id: `confirm-${account.starkKey}` });
      const button = el("button", { type: "button", disabled: "" }, "Register Stark key");
      confirm.addEventListener("change", () => (button.disabled = !confirm.checked));
      button.addEventListener("click", async () => {
        button.disabled = true;
        log.replaceChildren(el("p", {}, "Confirm the transaction in your wallet…"));
        try {
          const hash = await registerStarkKey(conn.signer, account.starkKey, account.registrationSignature);
          log.replaceChildren();
          report(notice("ok", "Stark key registered to ", el("code", {}, conn.address), "."), txLink(hash));
          refresh();
        } catch (err) {
          log.replaceChildren(notice("danger", errorMessage(err)));
          button.disabled = !confirm.checked;
        }
      });
      card.append(
        notice(
          "info",
          "This Stark key is not linked to any Ethereum address yet, which is why withdrawals fail with " +
            "USER_UNREGISTERED. Registering sends one transaction from your wallet to the bridge (you pay gas) " +
            "and permanently links the key to your connected wallet.",
        ),
        el(
          "label",
          { class: "check", for: confirm.id },
          confirm,
          el("span", {}, "I confirm ", el("code", {}, conn.address), " is my wallet and I want these withdrawals sent to it."),
        ),
        button,
        log,
      );
      break;
    }
    case "ready-to-withdraw": {
      card.append(
        notice(
          "ok",
          state.balances.length > 0
            ? "Registered to your connected wallet. Finalise each withdrawal below; each is one transaction."
            : "Registered to your connected wallet. No pending withdrawals for this Stark key.",
        ),
      );
      for (const balance of state.balances) {
        const button = el("button", { type: "button" }, `Withdraw ${formatBalance(balance)}`);
        button.addEventListener("click", async () => {
          button.disabled = true;
          log.replaceChildren(el("p", {}, "Confirm the transaction in your wallet…"));
          try {
            const hash = await withdrawAsset(conn.signer, account.starkKey, balance.token);
            log.replaceChildren();
            report(notice("ok", `Withdrew ${formatBalance(balance)} to ${conn.address}.`), txLink(hash));
            refresh();
          } catch (err) {
            log.replaceChildren(notice("danger", errorMessage(err)));
            button.disabled = false;
          }
        });
        card.append(button);
      }
      card.append(log);
      break;
    }
    case "registered-elsewhere":
      card.append(
        notice(
          "warn",
          "This Stark key is already registered to ",
          el("code", {}, status.registeredTo),
          ", not your connected wallet. Withdrawals for this key can only be sent to that address and the " +
            "registration cannot be changed. If that address is yours, connect it instead; otherwise contact " +
            "Immutable support through the official support site.",
        ),
      );
      break;
    case "no-funds":
      card.append(el("p", { class: "muted" }, "No pending withdrawals for this Stark key."));
      break;
  }
  return card;
}

function accountsSection(conn: Connection, accounts: DerivedAccount[]): HTMLElement {
  const body = el("div", {}, el("p", {}, "Checking the bridge for pending withdrawals…"));
  const activity = el("div", { class: "activity", "aria-live": "polite" });
  const container = section("4. Register and withdraw", body, activity);
  const report = (...nodes: Node[]) => activity.append(...nodes);

  const render = async () => {
    try {
      const states = await Promise.all(accounts.map((a) => getAccountState(conn.provider, a.starkKey)));
      const withFunds = accounts
        .map((account, i) => ({ account, state: states[i] }))
        .filter(({ state }) => ALLOW_REGISTRATION_WITHOUT_FUNDS || state.balances.length > 0);

      if (withFunds.length === 0) {
        body.replaceChildren(
          notice(
            "info",
            el("strong", {}, "No pending withdrawals found for this wallet."),
            el(
              "p",
              {},
              "Either the withdrawals have already been finalised, or this is not the wallet you used with " +
                "Immutable X. If support gave you a Stark key, compare it with the key below.",
            ),
          ),
          ...accounts.map((a) => starkKeyLabel(a.starkKey)),
          checkedTokensNote(),
        );
        return;
      }
      body.replaceChildren(
        ...withFunds.map(({ account, state }) => accountCard(conn, account, state, report, render)),
        checkedTokensNote(),
      );
    } catch (err) {
      const retry = el("button", { type: "button" }, "Try again");
      retry.addEventListener("click", () => {
        body.replaceChildren(el("p", {}, "Checking the bridge for pending withdrawals…"));
        void render();
      });
      const detail = rpcFailureDetail(err) ?? errorMessage(err);
      body.replaceChildren(
        notice(
          "danger",
          el("strong", {}, "Could not read your pending withdrawals from the bridge."),
          el(
            "p",
            {},
            "Your wallet's network connection returned an error, so nothing was checked and nothing was sent. " +
              "Try again in a moment. If it keeps failing, check your wallet's Ethereum Mainnet network settings.",
          ),
          el("p", {}, el("code", {}, detail)),
        ),
        retry,
      );
    }
  };
  void render();
  return container;
}

// ---------------------------------------------------------------------------

function start(): void {
  app.replaceChildren(header());
  if (!ALLOWED_HOSTNAMES.includes(location.hostname)) {
    app.append(blockedHost());
    return;
  }
  if (ALLOW_REGISTRATION_WITHOUT_FUNDS) {
    app.append(
      notice(
        "danger",
        el("strong", {}, "Testing mode: registration without pending withdrawals."),
        el(
          "p",
          {},
          "This page was opened with ?allow-registration-without-funds, so it offers to register Stark keys that " +
            "have no pending withdrawals in the checked tokens. Registration is permanent and costs gas. If you " +
            "did not add this to the address yourself, remove it and reload the page.",
        ),
      ),
    );
  }

  // Once connected, a different account, a locked wallet or a network change invalidates
  // everything derived so far.
  window.ethereum?.on?.("accountsChanged", (accounts) => {
    if (connectedAddress === null) return;
    const [current] = (accounts as string[] | undefined) ?? [];
    if (!current || getAddress(current) !== connectedAddress) location.reload();
  });
  // Wallets emit chainChanged after resolving wallet_switchEthereumChain, which can be after the
  // page has already reconnected on mainnet; only a move off mainnet invalidates the connection.
  window.ethereum?.on?.("chainChanged", (chainId) => {
    if (connectedAddress === null) retryConnect?.();
    else if (BigInt(chainId as string) !== MAINNET_CHAIN_ID) location.reload();
  });

  const intro = disclaimers(() => {
    intro.querySelectorAll("input, button").forEach((n) => n.setAttribute("disabled", ""));
    app.append(
      connectSection((conn) => {
        app.append(deriveSection(conn, (accounts) => app.append(accountsSection(conn, accounts))));
      }),
    );
  });
  app.append(intro);
}

start();
