import Defaults
import Foundation
import Testing

@testable import Retain

/// What Settings is allowed to write down, and what it must not throw away.
///
/// Both tests here are for faults that were found on the owner's own machine,
/// and both had the same shape: something typed or something absent was taken
/// as an instruction, and a working configuration was replaced by it in
/// `UserDefaults` — where it stayed after the window closed, after the app
/// quit, and after the next launch, with nothing on screen to connect the
/// symptom to the cause.
@Suite("Settings persistence", .serialized)
struct SettingsPersistenceTests {

    private func restoring(_ body: () async -> Void) async {
        let address = Defaults[.languageModelAddress]
        let model = Defaults[.languageModelName]
        // A usable address to start from. `refreshModels` builds an endpoint
        // before it asks anything, so a test that inherits a refused address
        // from the machine it runs on measures nothing.
        Defaults[.languageModelAddress] = "http://localhost:1234/v1"
        await body()
        Defaults[.languageModelAddress] = address
        Defaults[.languageModelName] = model
    }

    // MARK: - The address

    @Test("An address Retain may not open is not stored")
    func aRefusedAddressIsNotStored() async {
        await restoring {
            Defaults[.languageModelAddress] = "http://localhost:1234/v1"

            let model = await SettingsModel()
            // Hard rule 9: anything that is not this Mac is refused, not warned
            // about. It was still written to `UserDefaults`, and the next
            // launch came up pointing at it.
            await MainActor.run { model.address = "https://api.openai.com/v1" }

            #expect(Defaults[.languageModelAddress] == "http://localhost:1234/v1")
            // The field keeps what was typed — it could not be edited
            // otherwise — and says why it is not being used.
            #expect(await model.address == "https://api.openai.com/v1")
            #expect(await model.addressRejection != nil)
        }
    }

    @Test("An address Retain may open replaces the old one")
    func anAcceptableAddressIsStored() async {
        await restoring {
            let model = await SettingsModel()
            await MainActor.run { model.address = "http://localhost:4321/v1" }
            #expect(Defaults[.languageModelAddress] == "http://localhost:4321/v1")
        }
    }

    // MARK: - The model

    @Test("A server that did not answer does not clear the chosen model")
    func anEmptyListKeepsTheModel() async {
        await restoring {
            Defaults[.languageModelName] = "openai/gpt-oss-20b"

            let model = await SettingsModel(
                makeBackend: { _ in SettingsStubBackend(models: []) }
            )
            await model.refreshModels()

            // An unreachable server, a wrong address and a missing API key all
            // produce an empty list. One 401 used to delete a choice made weeks
            // ago, and the title bar then said "No model".
            #expect(await model.selectedModel == "openai/gpt-oss-20b")
            #expect(Defaults[.languageModelName] == "openai/gpt-oss-20b")
        }
    }

    @Test("A server with one model chooses it when nothing is chosen")
    func oneModelIsAdopted() async {
        await restoring {
            Defaults[.languageModelName] = ""

            let model = await SettingsModel(
                makeBackend: { _ in
                    SettingsStubBackend(models: [LanguageModelDescriptor(id: "only", contextLength: nil)])
                }
            )
            await model.refreshModels()

            #expect(await model.selectedModel == "only")
        }
    }

    @Test("A model the server no longer has is given up, but only on an answer")
    func aMissingModelIsGivenUp() async {
        await restoring {
            Defaults[.languageModelName] = "gone"

            let model = await SettingsModel(
                makeBackend: { _ in
                    SettingsStubBackend(models: [
                        LanguageModelDescriptor(id: "one", contextLength: nil),
                        LanguageModelDescriptor(id: "two", contextLength: nil),
                    ])
                }
            )
            await model.refreshModels()

            // The server answered and the model is not among what it offers.
            // With two to choose from there is nothing honest to pick.
            #expect(await model.selectedModel.isEmpty)
        }
    }
}
