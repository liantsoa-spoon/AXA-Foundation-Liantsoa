/**
 * @description       : Jest tests for the consentCheckbox component.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 20-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   20-10-2026   LAN      Initial version
 **/
import { createElement } from "lwc";
import ConsentCheckbox from "c/consentCheckbox";

const PROPERTIES = {
  prefix: "I accept the",
  linkLabel: "Terms and Conditions",
  url: "https://example.com/terms",
  errorMessage: "You must accept the Terms and Conditions."
};

const createComponent = (properties = PROPERTIES) => {
  const element = createElement("c-consent-checkbox", { is: ConsentCheckbox });
  Object.assign(element, properties);
  document.body.appendChild(element);
  return element;
};

const tick = () => Promise.resolve();

describe("c-consent-checkbox", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("links the label to the document in a new tab", () => {
    const element = createComponent();

    const link = element.shadowRoot.querySelector("a");
    expect(link.href).toBe(PROPERTIES.url);
    expect(link.target).toBe("_blank");
    expect(link.textContent).toBe(PROPERTIES.linkLabel);
  });

  it("shows the link label as plain text without document", () => {
    const element = createComponent({ ...PROPERTIES, url: undefined });

    expect(element.shadowRoot.querySelector("a")).toBeNull();
    expect(element.shadowRoot.textContent).toContain(PROPERTIES.linkLabel);
  });

  it("reports an error while unchecked", async () => {
    const element = createComponent();

    expect(element.reportValidity()).toBe(false);
    await tick();

    expect(element.shadowRoot.querySelector(".slds-has-error")).not.toBeNull();
    expect(
      element.shadowRoot.querySelector(".slds-form-element__help").textContent
    ).toContain(PROPERTIES.errorMessage);
  });

  it("notifies the parent and clears the error once checked", async () => {
    const element = createComponent();
    const handler = jest.fn();
    element.addEventListener("consentchange", handler);
    element.reportValidity();
    await tick();

    const input = element.shadowRoot.querySelector("input");
    input.checked = true;
    input.dispatchEvent(new CustomEvent("change"));
    await tick();

    expect(handler.mock.calls[0][0].detail).toEqual({ checked: true });
    expect(element.checked).toBe(true);
    expect(element.reportValidity()).toBe(true);
    expect(element.shadowRoot.querySelector(".slds-has-error")).toBeNull();
  });
});
