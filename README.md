# Teams Phone for D365 Contact Center

A friendly, point-and-click setup wizard that brings a **Teams Phone** number into your **Dynamics 365 Contact Center Voice channel** — without you having to read a single Microsoft doc.

You install it once, open it from inside D365, fill in two boxes, and the wizard does the rest.

![Wizard screenshot](docs/01image.png)

> **Prefer not to install anything?** Skip the HTML wizard and paste [**docs/COPY-PASTE-PROMPT.md**](docs/COPY-PASTE-PROMPT.md) into Microsoft Scout, GitHub Copilot CLI, Claude or any tool-capable LLM. It interviews you, then does the whole setup (Entra app, resource account, license, binding, number assignment, D365 sync and verification) for you. You just paste, answer questions and approve sign-ins.

---

## Why this exists

Wiring a Teams phone number into the D365 Voice channel officially involves:

- a half-page PowerShell script you have to hand-edit,
- an Entra (Azure AD) app you have to register and consent,
- four different admin portals,
- and three GUIDs that nobody remembers.

This wizard collapses all of that into **one screen**. It auto-detects everything it can, asks you only for the things it genuinely cannot guess, and generates a ready-to-paste PowerShell script for your Teams admin.

---

## Before you start

You need the following **once per tenant**. None of this is created by the wizard — these are the prerequisites the official Microsoft flow assumes.

| You need | Why |
|---|---|
| **Dynamics 365 Contact Center** with the **Voice channel** already provisioned | The wizard plugs into your existing voice setup (it does not create one). |
| A Teams **service number** (usage: **Voice app**) | The wizard does **not** order phone numbers. They must already exist in your Teams tenant. User (DID) numbers are not supported. A Calling Plan service number with *Voice app* usage works with no call queue or auto attendant (verified). → [Get service numbers for Teams](https://learn.microsoft.com/microsoftteams/getting-service-phone-numbers) |
| **Teams Administrator** + **Global Administrator** in your Microsoft 365 tenant | Needed to register the app and run the onboarding script. Use the *tenant's own* admin account, not a guest or your home-tenant account. |
| One free **Microsoft Teams Phone Resource Account** license | Needed to attach the phone number to the resource account. |
| **PowerShell 7+** with the `MicrosoftTeams` module (and Microsoft Graph modules, or access to PSGallery) | The generated script installs what it needs. If PSGallery is blocked by policy, install the modules from your internal feed first. |

---

## Install the wizard (5 minutes, one time)

### Step 1 — Download the solution

Grab one of the two zips from the latest release:

➡️ **[Download latest release](https://github.com/moliveirapinto/teams-phone-d365-wizard/releases/latest)**

| File | When to pick this one |
|---|---|
| `mauTeamsPhoneSetup_*.zip` (**unmanaged**) | **Recommended for most people.** You can edit the wizard, restyle it, change copy, or add fields directly in your environment. Easier to uninstall by simply deleting the components. |
| `mauTeamsPhoneSetup_*_managed.zip` (managed) | Strict ALM environments where admins want a sealed, read-only solution they can cleanly remove. The wizard cannot be customized in-place — you'd need to re-import an unmanaged version to tweak it. |

Not sure? Pick the **unmanaged** zip. You can always switch later.

### Step 2 — Import it into your environment

1. Open the **Power Apps maker portal** → https://make.powerapps.com
2. In the top-right environment picker, **select the same environment that hosts your D365 Contact Center**.
3. In the left menu, click **Solutions**.
4. Click **Import solution** at the top.
5. Click **Browse**, choose the `.zip` you just downloaded, then click **Next** and **Import**.
6. Wait for the green **"Solution imported successfully"** banner (usually under a minute).

That's it. The wizard is now installed in your environment.

---

## Open the wizard

After import, the wizard lives at a fixed URL inside your D365 environment:

```
https://<your-org>.crm.dynamics.com/WebResources/mau_TeamsPhoneSetup.html
```

Replace `<your-org>` with whatever appears in your D365 URL (for example, `contoso` if your D365 home page is `https://contoso.crm.dynamics.com`).

> 💡 **Tip — bookmark it.** Once you have the working URL, save it as a browser bookmark called "Teams Phone setup" so admins can find it again next time.

> 💡 **Tip — easier way to find the URL.** If you don't know your org URL by heart:
> 1. Open the **Power Apps maker portal** → **Solutions** → click **Teams Phone for D365 Contact Center**.
> 2. Click **Web resources** in the left panel.
> 3. Click `mau_TeamsPhoneSetup.html` → copy the **URL** field — that's the link to share with your Teams admin.

---

## Use the wizard

When the page loads it auto-fills almost everything. You will be asked for:

1. **A friendly display name** for the resource account (anything — e.g. "Sales Hotline").
2. **An email address** for the resource account (e.g. `saleshotline@yourcompany.com` — the wizard creates the user for you).
3. **The Teams phone number** you already have provisioned in Teams (in `+E.164` format, e.g. `+15551234567`).

The wizard then walks you through five short steps in order:

1. **Enter values** — fill the form, click **Generate script**.
2. **Run PowerShell** — your Teams admin clicks **Copy script** or **Download .ps1**, runs it once in a PowerShell window. It installs everything, signs in, creates the resource account, binds Teams, and assigns the number.
3. **Assign license** — opens the M365 Admin Center pre-filtered to the new account so you can attach the free Teams Phone Resource Account license in two clicks.
4. **Sync from Teams in D365** — deep-links to **Customer Service workspace → Admin Center → Channels → Phone numbers → Advanced → Teams phone system** so D365 can pull the number it just created.
5. **Attach to workstream** — opens the workstream/queue editor where you point the new number at an existing voice queue.

### Calling Plan numbers: assign the number from the Phone numbers page

For Calling Plan numbers the script deliberately does **not** assign the number. Do it here:

**Teams admin center → Voice → Phone numbers →** select the number **→ Edit → Assigned to: Resource account →** search your account **→ Add → Apply**.

> ⚠️ The **Assign a phone number** button on the resource account's own page opens a panel whose *Phone number type* dropdown is disabled. Use the Phone numbers page instead.

### Before you click Sync: verify the Teams side

Sign in to Teams PowerShell (`Connect-MicrosoftTeams`; add `-UseDeviceAuthentication` for a clean or InPrivate browser session) and check:

```powershell
Get-CsOnlineApplicationInstance -Identity <resource-account-upn> | fl AcsResourceId,ApplicationId,PhoneNumber
```

| Field | Must be |
|---|---|
| `ApplicationId` | The **Dynamics App ID** shown in D365 (Channels → Phone numbers → Advanced → Teams phone system). **Not** `11cd3e2e-fccb-42ad-ad00-878b93575e07` (that is the Call Queue app). |
| `AcsResourceId` | The **Azure Communication Services resource ID** from the same D365 page. If it shows `ACS_Resource_ID_Not_Set`, D365 cannot see the account. |
| `PhoneNumber` | `tel:+<your number>` |

If either ID is wrong, fix it:

```powershell
$ra = Get-CsOnlineApplicationInstance -Identity <resource-account-upn>
Set-CsOnlineApplicationInstance  -Identity  $ra.ObjectId -ApplicationId <DynamicsAppId>
Sync-CsOnlineApplicationInstance -ObjectId  $ra.ObjectId -ApplicationId <DynamicsAppId> -AcsResourceId <AcsResourceId>
```

### How you know it worked

After **Sync from Teams** (allow up to ~5 minutes, then refresh), the number appears under **Channels → Phone numbers** with *Type: Teams* and *Status: Ready for setup*. Then attach it to a voice workstream.

---

## Updating to a new version


When a new release is published:

1. Download the new zip (**same flavour you originally installed** — unmanaged or managed) from [Releases](https://github.com/moliveirapinto/teams-phone-d365-wizard/releases).
2. In **Power Apps → Solutions → Import solution**, upload the new zip on top of the old one. Power Platform will prompt **"Upgrade"** — accept it.
3. The wizard URL stays the same. Just refresh the page.

> ⚠️ Don't mix flavours. You cannot import a managed zip on top of an unmanaged one (or vice-versa) — Power Platform will reject it. If you really need to switch, uninstall the old solution first.

---

## Uninstalling

**Power Apps maker portal → Solutions →** check **Teams Phone for D365 Contact Center → Delete**. Web resources will be removed; resource accounts and phone numbers you created in Teams are *not* touched.

---

## Troubleshooting

| Symptom | What to do |
|---|---|
| Wizard page shows **"Voice channel not detected"** | The Voice channel has not been provisioned in this environment yet. Use the link the wizard shows to open the Customer Service workspace and complete voice setup first. |
| PowerShell script fails with **"insufficient privileges"** | The person running the script is not a Teams Administrator + Global Administrator. Have the right person re-run it. |
| `New-CsOnlineApplicationInstance: ... license required` | The resource account is missing the Teams Phone Resource Account license. Go back to **Step 3** of the wizard and assign it, then re-run the script. |
| The number does not appear in D365 after the script succeeds | Wait 1–2 minutes, then click **Step 4 — Sync from Teams in D365** in the wizard. Teams → D365 sync is not instant; in testing it took a few minutes after the Teams side was fixed. Refresh the Phone numbers page. |
| Sync says **"No new phone numbers were found in Teams Admin Center to sync"** | This message is generic. It also appears when D365 cannot match the account. Run the *verify the Teams side* check above: the usual causes are a wrong `ApplicationId` or `AcsResourceId` = `ACS_Resource_ID_Not_Set`. Fix with `Set-` / `Sync-CsOnlineApplicationInstance ... -AcsResourceId`, wait a few minutes, sync again. |
| Sync response is `TotalTeamsNumbers: null` (browser dev tools, `CCaaS_SynchronizePhoneNumbers`) | Same root cause as above: D365 found no Teams numbers bound to the ACS resource. |
| **Resource account type** shows **Other** in Teams admin | That is expected for an account bound to the Dynamics app. **Do not** change it to *Call queue* or *Auto attendant* in the Teams UI: it swaps the account's `ApplicationId` to the Call Queue app and breaks the D365 binding. If that already happened, re-run the `Set-` / `Sync-CsOnlineApplicationInstance` commands above. |
| Call queue picker shows **"No results"** for the resource account | Same reason: the account is bound to the Dynamics app, not the Call Queue app. You do not need a call queue for this flow. |
| D365 banner: **"Some components of this app require you to sign in"** | Click **Sign in** once (it opens a short Power Apps auth popup; allow popups). It is not what blocks the sync, so continue even if the banner stays. |
| `Install-Module` fails: **"Unable to find repository 'PSGallery'"** | PSGallery is blocked or unregistered on this machine. Install the Graph modules from your internal feed, or run the Entra step from a machine that has PSGallery. |
| **"You don't have access to the Teams admin center"** (`INVALID_PRIVILEGE`) right after sign-in | Usually a transient deep-link error. Open the Teams admin center dashboard first and navigate with the menu. If it persists, the account lacks the Teams Administrator role. |

For deeper reading on the underlying flow:

- 📘 [Configure Teams Phone in the voice channel (Microsoft Learn)](https://learn.microsoft.com/dynamics365/contact-center/administer/configure-teams-phone-in-voice-channel)
- 📘 [Microsoft sample onboarding script (GitHub)](https://github.com/microsoft/Dynamics365-Apps-Samples/blob/master/contact-center/TeamsPhoneSystem-TeamsAdminCenterOnboardScript.ps1)

---

## For contributors

> Skip this section if you just want to use the wizard.

The repo also contains the source web resource and the two helper scripts used to publish and pack new releases.

```
webresource/
  mau_TeamsPhoneSetup.html      # the wizard UI (the one and only thing end-users see)
  mau_teamsphone_example.png    # screenshot used inside the wizard

dist/                           # the built solution zips that go on Releases
docs/                           # README assets

upload.ps1                      # publish the HTML + PNG into a Dataverse env
create-solution.ps1             # repack the solution and export new zips into dist/
```

Both helper scripts are tenant-agnostic — they take `-OrgUrl` and use `az account get-access-token` for auth. Typical dev loop:

```powershell
az login --tenant <your-tenant>
.\upload.ps1          -OrgUrl https://<your-org>.crm.dynamics.com
.\create-solution.ps1 -OrgUrl https://<your-org>.crm.dynamics.com -Export
```

---

## License

MIT.
