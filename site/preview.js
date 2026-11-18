const controls = document.querySelector(".preview-controls");
const tabs = [...controls.querySelectorAll("button")];
const panels = tabs.map((tab) => document.getElementById(tab.getAttribute("aria-controls")));

function selectPreview(index, moveFocus = false) {
  tabs.forEach((tab, position) => {
    const selected = position === index;
    tab.setAttribute("aria-selected", String(selected));
    tab.tabIndex = selected ? 0 : -1;
    panels[position].hidden = !selected;
  });

  if (moveFocus) tabs[index].focus();
}

controls.setAttribute("role", "tablist");

tabs.forEach((tab, index) => {
  tab.setAttribute("role", "tab");
  panels[index].setAttribute("role", "tabpanel");
  panels[index].setAttribute("aria-labelledby", tab.id);
  panels[index].tabIndex = 0;

  tab.addEventListener("click", () => selectPreview(index));
  tab.addEventListener("keydown", (event) => {
    const destinations = {
      ArrowLeft: (index + tabs.length - 1) % tabs.length,
      ArrowRight: (index + 1) % tabs.length,
      Home: 0,
      End: tabs.length - 1,
    };
    if (!Object.hasOwn(destinations, event.key)) return;

    event.preventDefault();
    selectPreview(destinations[event.key], true);
  });
});

selectPreview(0);
controls.hidden = false;
