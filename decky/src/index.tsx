import { ButtonItem, Navigation, PanelSection, PanelSectionRow, staticClasses } from "@decky/ui";
import { callable, definePlugin } from "@decky/api";
import { useCallback, useEffect, useState } from "react";
import { FaHeartbeat } from "react-icons/fa";
import qrcode from "qrcode-generator";

interface SetupStatus {
  version: string;
  sourceCommit: string;
  trackerState: string;
  running: boolean;
  phoneUrl: string | null;
  pcsx2Installed: boolean;
  pineEnabled: boolean | null;
  pineSlot: number | null;
  message: string;
}

const getStatus = callable<[], SetupStatus>("get_status");
const setRunning = callable<[running: boolean], SetupStatus>("set_running");

function Content() {
  const [status, setStatus] = useState<SetupStatus>();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string>();
  const refresh = useCallback(async () => {
    setLoading(true);
    setError(undefined);
    try {
      setStatus(await getStatus());
    } catch {
      setError("Unable to read plugin status. Try Refresh, or check the plugin log.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void refresh();
    const interval = setInterval(() => void refresh(), 3000);
    return () => clearInterval(interval);
  }, [refresh]);
  let qrImage: string | undefined;
  if (status?.phoneUrl) {
    const qr = qrcode(0, "M");
    qr.addData(status.phoneUrl);
    qr.make();
    qrImage = qr.createDataURL(4);
  }

  return (
    <PanelSection title="Phone view">
      <PanelSectionRow>
        <div aria-live="polite" style={{ overflowWrap: "anywhere" }}>
          {error && <p role="alert">{error}</p>}
          {!status && !error && <p>Reading plugin status…</p>}
          {status && <>
            <p>{status.message}</p>
            <p>Reader: {status.trackerState}</p>
            {qrImage && <img src={qrImage} alt="Scan to open the tracker on your network" style={{ width: 220, maxWidth: "100%" }} />}
            {status.phoneUrl && <p>{status.phoneUrl}</p>}
            <p>PCSX2 AppImage: {status.pcsx2Installed ? "Found" : "Not found"}</p>
            <p>PINE setting: {status.pineEnabled === null ? "Unavailable" : status.pineEnabled ? "Enabled" : "Disabled"}
              {status.pineSlot !== null && ` (slot ${status.pineSlot})`}</p>
            <p>Version {status.version} · Commit {status.sourceCommit.slice(0, 12)}</p>
          </>}
        </div>
      </PanelSectionRow>
      {status?.phoneUrl && <PanelSectionRow>
        <ButtonItem layout="below" onClick={() => Navigation.NavigateToExternalWeb(status.phoneUrl!)}>Open tracker on Deck</ButtonItem>
      </PanelSectionRow>}
      {status && <PanelSectionRow>
        <ButtonItem layout="below" onClick={async () => {
          try { setStatus(await setRunning(!status.running)); }
          catch { setError("Unable to change phone view state. Check the plugin log."); }
        }}>{status.running ? "Stop phone view and reader" : "Start phone view and reader"}</ButtonItem>
      </PanelSectionRow>}
      <PanelSectionRow>
        <ButtonItem layout="below" disabled={loading} onClick={() => void refresh()}>
          {loading ? "Refreshing…" : "Refresh"}
        </ButtonItem>
      </PanelSectionRow>
    </PanelSection>
  );
}

export default definePlugin(() => ({
  name: "Outbreak Tracker",
  titleView: <div className={staticClasses.Title}>Outbreak Tracker</div>,
  content: <Content />,
  icon: <FaHeartbeat />,
  onDismount() {},
}));
