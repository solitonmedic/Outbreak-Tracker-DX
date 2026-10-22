import { ButtonItem, PanelSection, PanelSectionRow, staticClasses } from "@decky/ui";
import { callable, definePlugin } from "@decky/api";
import { useCallback, useEffect, useState } from "react";
import { FaHeartbeat } from "react-icons/fa";

interface SetupStatus {
  version: string;
  sourceCommit: string;
  trackerState: "pending";
  pcsx2Installed: boolean;
  pineEnabled: boolean | null;
  pineSlot: number | null;
  message: string;
}

const getStatus = callable<[], SetupStatus>("get_status");

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

  useEffect(() => { void refresh(); }, [refresh]);

  return (
    <PanelSection title="Setup status">
      <PanelSectionRow>
        <div aria-live="polite" style={{ overflowWrap: "anywhere" }}>
          {error && <p role="alert">{error}</p>}
          {!status && !error && <p>Reading plugin status…</p>}
          {status && <>
            <p>{status.message}</p>
            <p>PCSX2 AppImage: {status.pcsx2Installed ? "Found" : "Not found"}</p>
            <p>PINE setting: {status.pineEnabled === null ? "Unavailable" : status.pineEnabled ? "Enabled" : "Disabled"}
              {status.pineSlot !== null && ` (slot ${status.pineSlot})`}</p>
            <p>Version {status.version} · Commit {status.sourceCommit.slice(0, 12)}</p>
          </>}
        </div>
      </PanelSectionRow>
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
