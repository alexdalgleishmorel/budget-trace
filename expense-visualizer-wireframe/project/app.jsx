/* global React */
const { useState: useAppState } = React;
const UA = window.EVUtils;
const IA = window.EVIcons;
const S1 = window.EVScreens1;
const S2 = window.EVScreens2;
const M = window.EVModals;
const C = window.EVChrome;

// One App = one frame's interactive inside. Tab switches, modals open.
function App({ compact, startTab = "expenses", initialModal = null, empty = {} }) {
  const [tab, setTab] = useAppState(startTab);
  const [modal, setModal] = useAppState(initialModal);

  const isEmpty = empty[tab];

  const screen = (() => {
    if (tab === "categories") return <S1.CategoriesScreen compact={compact} empty={isEmpty} onOpenCreate={() => setModal("new-cat")} onOpenEdit={() => setModal("edit-cat")} />;
    if (tab === "expenses") return <S1.ExpensesScreen compact={compact} empty={isEmpty} onOpenEdit={() => setModal("tx")} onOpenImport={() => setModal("import")} />;
    if (tab === "widgets") return <S2.WidgetsScreen compact={compact} empty={isEmpty} onOpenAdd={() => setModal("add-widget")} onOpenSwitcher={() => setModal("switcher")} />;
    if (tab === "insights") return <S2.InsightsScreen compact={compact} empty={isEmpty} />;
    return null;
  })();

  const hdr = compact ? null : (
    <aside style={{
      width: 220, padding: 22, gap: 4,
      display: "flex", flexDirection: "column",
      borderRight: "1px solid var(--glass-border)",
      flexShrink: 0,
      position: "relative", zIndex: 2,
    }}>
      <div style={{ marginBottom: 28 }}><UA.BrandCompact /></div>
      <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
        {UA.TAB_LIST.map(t => (
          <UA.SidebarTab key={t.id} icon={t.icon} label={t.label} active={tab === t.id} onClick={() => setTab(t.id)} />
        ))}
      </div>
      <div style={{ flex: 1 }} />
      <button onClick={() => setModal("account")} style={{
        display: "flex", alignItems: "center", gap: 10, height: 42, padding: "0 14px",
        borderRadius: 12, background: "transparent", border: "1px solid var(--glass-border)",
        color: "var(--ink-2)", fontFamily: "inherit", fontSize: 14, fontWeight: 500, cursor: "pointer",
      }}>
        <IA.User size={16} />Account
      </button>
    </aside>
  );

  const bottomNav = !compact ? null : (
    <div className="glass-strong" style={{
      position: "absolute", left: 12, right: 12, bottom: 14,
      borderRadius: 24, padding: "6px 4px",
      display: "flex", gap: 2,
      zIndex: 5,
    }}>
      {UA.TAB_LIST.map(t => (
        <UA.MobileTab key={t.id} icon={t.icon} label={t.label} active={tab === t.id} onClick={() => setTab(t.id)} />
      ))}
    </div>
  );

  return (
    <div style={{ display: "flex", height: "100%", position: "relative" }}>
      {hdr}
      <main style={{ flex: 1, minWidth: 0, position: "relative", overflow: "hidden" }}>
        {screen}
        {bottomNav}
      </main>
      {modal === "account" && <M.AccountModal onClose={() => setModal(null)} />}
      {modal === "new-cat" && <M.CategoryModal onClose={() => setModal(null)} />}
      {modal === "edit-cat" && <M.CategoryModal edit onClose={() => setModal(null)} />}
      {modal === "tx" && <M.TxModal onClose={() => setModal(null)} />}
      {modal === "add-widget" && <M.AddWidgetDrawer onClose={() => setModal(null)} />}
      {modal === "switcher" && <M.DashSwitcher onClose={() => setModal(null)} />}
      {modal === "import" && <M.ImportModal onClose={() => setModal(null)} />}
      {modal === "import-success" && <M.ImportModal state="success" onClose={() => setModal(null)} />}
      {modal === "import-error" && <M.ImportModal state="error" onClose={() => setModal(null)} />}
    </div>
  );
}

window.EVApp = { App };
