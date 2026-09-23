import { BrowserProvider, formatUnits, getAddress, toBeHex, type Eip1193Provider, type Signer } from "ethers";
import {
  BRIDGE_ADDRESS,
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
    ethereum?: Eip1193Provider & { on?: (event: string, handler: () => void) => void };
  }
}

/** The page refuses to run anywhere but the user's own machine. */
const ALLOWED_HOSTNAMES = ["localhost", "127.0.0.1"];
const ETHERSCAN = "https://etherscan.io";

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

function errorMessage(err: unknown): string {
  const e = err as { code?: string | number; shortMessage?: string; message?: string };
  if (e.code === "ACTION_REJECTED" || e.code === 4001) return "You rejected the request in your wallet.";
  return e.shortMessage ?? e.message ?? String(err);
}

// ---------------------------------------------------------------------------
// Page sections
// ---------------------------------------------------------------------------

function header(): HTMLElement {
  return el(
    "header",
    {},
    el("h1", {}, "Register your Immutable X Stark key"),
    el(
      "p",
      { class: "lede" },
      "For Immutable X users whose withdrawal fails with USER_UNREGISTERED. This page links your Stark key to your " +
        "Ethereum wallet on the Immutable X bridge, then lets you finalise your pending withdrawals to that wallet.",
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

function connectSection(onConnected: (c: Connection) => void): HTMLElement {
  const status = el("div", { class: "status" });
  const button = el("button", { type: "button" }, "Connect wallet");

  button.addEventListener("click", async () => {
    status.replaceChildren();
    if (!window.ethereum) {
      status.append(notice("danger", "No browser wallet found. Install or enable your wallet extension and reload this page."));
      return;
    }
    button.disabled = true;
    try {
      const provider = new BrowserProvider(window.ethereum);
      await provider.send("eth_requestAccounts", []);
      const problems = await checkDeployment(provider);
      if (problems.length > 0) {
        const switchButton = el("button", { type: "button" }, "Switch wallet to Ethereum Mainnet");
        switchButton.addEventListener("click", () =>
          provider.send("wallet_switchEthereumChain", [{ chainId: toBeHex(1) }]).catch(() => undefined),
        );
        status.append(notice("danger", ...problems.map((p) => el("p", {}, p))), switchButton);
        button.disabled = false;
        return;
      }
      const signer = await provider.getSigner();
      const address = getAddress(await signer.getAddress());
      status.append(notice("ok", "Connected: ", el("code", {}, address)));
      onConnected({ provider, signer, address });
    } catch (err) {
      status.append(notice("danger", errorMessage(err)));
      button.disabled = false;
    }
  });

  return section(
    "2. Connect your wallet",
    el("p", {}, "Connect the wallet you used with Immutable X, on Ethereum Mainnet."),
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
  const status = classify(state, conn.address);
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
      card.append(notice("ok", "Registered to your connected wallet. Finalise each withdrawal below; each is one transaction."));
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
        .filter(({ state }) => state.balances.length > 0);

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
        );
        return;
      }
      body.replaceChildren(...withFunds.map(({ account, state }) => accountCard(conn, account, state, report, render)));
    } catch (err) {
      body.replaceChildren(notice("danger", errorMessage(err)));
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

  // A wallet or network change invalidates everything derived so far.
  window.ethereum?.on?.("accountsChanged", () => location.reload());
  window.ethereum?.on?.("chainChanged", () => location.reload());

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
