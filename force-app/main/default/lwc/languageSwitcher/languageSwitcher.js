/**
 * @description       : Lets the current portal user switch between English and French.
 * @author            : Liantsoa Andrianilana
 * @last modified on  : 08-10-2026
 * @last modified by  : Liantsoa Andrianilana
 *
 * Modifications Log
 * Ver   Date         Author   Modification
 * 1.0   07-10-2026   LAN      Initial version
 * 1.1   08-10-2026   LAN      Hold the texts in LABELS, in English and French, instead of Custom Labels
 **/
import { LightningElement } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import USER_LANGUAGE from "@salesforce/i18n/lang";
import updateLanguage from "@salesforce/apex/LanguageController.updateLanguage";

// Every user-facing string, in English and in French: the language of the connected user is used.
const LABELS = {
  en: {
    ariaLabel: "Language",
    languages: {
      english: "EN",
      french: "FR"
    },
    feedback: {
      errorTitle: "The language could not be changed",
      errorMessage: "Please try again. If the problem persists, contact the organisation."
    }
  },

  fr: {
    ariaLabel: "Langue",
    languages: {
      english: "EN",
      french: "FR"
    },

    feedback: {
      errorTitle: "La langue n'a pas pu être modifiée",
      errorMessage: "Veuillez réessayer. Si le problème persiste, contactez l'organisation."
    }
  }
};

const USER_LANGUAGE_PREFIX = USER_LANGUAGE.toLowerCase().substring(0, 2);
const UI_LABELS = USER_LANGUAGE_PREFIX === "fr" ? LABELS.fr : LABELS.en;

const LANGUAGES = [
  { code: "en_US", prefix: "en", label: UI_LABELS.languages.english },
  { code: "fr", prefix: "fr", label: UI_LABELS.languages.french }
];

export default class LanguageSwitcher extends LightningElement {
  isLoading = false;

  get languageOptions() {
    return LANGUAGES.map((language) => {
      const isActive = language.prefix === USER_LANGUAGE_PREFIX;
      return {
        code: language.code,
        label: language.label,
        ariaCurrent: isActive ? "true" : null,
        className: isActive
          ? "language-switcher__button language-switcher__button_active"
          : "language-switcher__button"
      };
    });
  }

  get ariaLabel() {
    return UI_LABELS.ariaLabel;
  }

  async handleLanguageClick(event) {
    const languageCode = event.currentTarget.dataset.code;
    const isCurrentLanguage =
      event.currentTarget.getAttribute("aria-current") === "true";
    if (this.isLoading || isCurrentLanguage) {
      return;
    }

    this.isLoading = true;
    try {
      await updateLanguage({ languageCode });
      window.location.reload();
    } catch (error) {
      this.isLoading = false;
      this.dispatchEvent(
        new ShowToastEvent({
          title: UI_LABELS.feedback.errorTitle,
          message: UI_LABELS.feedback.errorMessage,
          variant: "error"
        })
      );
    }
  }
}