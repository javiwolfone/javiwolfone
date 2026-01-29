document.addEventListener("DOMContentLoaded", () => {
  const panelContainer = document.getElementById("panel-container")
  const playerListContent = document.getElementById("player-list-content")
  const closeButton = document.getElementById("close-button")
  const searchBar = document.getElementById("search-bar")
  const giveCarModal = document.getElementById("give-car-modal")
  const carModelInput = document.getElementById("car-model-input")
  const confirmGiveCarBtn = document.getElementById("confirm-give-car")
  const cancelGiveCarBtn = document.getElementById("cancel-give-car")
  const modalCloseBtn = document.getElementById("modal-close-btn")
  let targetIdForCar = null
  let spectatingPlayerId = null
  const frozenPlayerIds = {}
  let currentOpenMenu = null

  const postAction = (action, data = {}) => {
    fetch(`https://${GetParentResourceName()}/${action}`, {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=UTF-8" },
      body: JSON.stringify(data),
    }).catch(console.error)
  }

  const populatePlayerList = (players) => {
    playerListContent.innerHTML = ""
    if (!players) return
    const sortedPlayerIds = Object.keys(players).sort((a, b) => Number.parseInt(a) - Number.parseInt(b))

    for (const id of sortedPlayerIds) {
      const player = players[id]
      const row = document.createElement("div")
      row.className = "player-row"
      row.dataset.id = id
      row.dataset.name = player.name.toLowerCase()
      row.dataset.permid = player.permId

      const isFrozen = frozenPlayerIds[id]
      const isSpectating = spectatingPlayerId === id

      row.innerHTML = `
        <div class="player-info">
          <span class="player-name">${player.name}</span>
          <span class="player-ids">[${id} | ${player.permId}]</span>
        </div>
        <div class="player-actions">
          <button class="action-trigger" data-action="toggleActions">
            <i data-lucide="more-horizontal"></i>
            Actions
          </button>
          <div class="actions-panel hidden">
            <div class="action-grid">
              <button class="action-btn" data-action="goto">
                <i data-lucide="navigation"></i>
                Go To
              </button>
              <button class="action-btn" data-action="bring">
                <i data-lucide="user-plus"></i>
                Bring
              </button>
              <button class="action-btn toggleable ${isFrozen ? "active" : ""}" data-action="freeze">
                <i data-lucide="snowflake"></i>
                ${isFrozen ? "Unfreeze" : "Freeze"}
              </button>
              <button class="action-btn toggleable ${isSpectating ? "active" : ""}" data-action="spectate">
                <i data-lucide="eye"></i>
                ${isSpectating ? "Stop" : "Spectate"}
              </button>
              <button class="action-btn" data-action="kick">
                <i data-lucide="user-x"></i>
                Kick
              </button>
              <button class="action-btn" data-action="giveCar">
                <i data-lucide="car"></i>
                Vehicle
              </button>
              <button class="action-btn" data-action="sendToDiscord">
                <i data-lucide="message-circle"></i>
                Discord
              </button>
            </div>
          </div>
        </div>
      `
      playerListContent.appendChild(row)
    }

    const lucide = window.lucide
    lucide.createIcons()
  }

  playerListContent.addEventListener("click", (e) => {
    const target = e.target.closest("button")
    if (!target) return

    const action = target.dataset.action
    if (!action) return

    const row = target.closest(".player-row")
    const targetId = row.dataset.id
    const actionsPanel = row.querySelector(".actions-panel")

    switch (action) {
      case "toggleActions":
        if (currentOpenMenu && currentOpenMenu !== actionsPanel) {
          currentOpenMenu.classList.add("hidden")
          currentOpenMenu.closest(".player-actions").querySelector(".action-trigger").classList.remove("active")
        }

        actionsPanel.classList.toggle("hidden")
        target.classList.toggle("active")
        currentOpenMenu = actionsPanel.classList.contains("hidden") ? null : actionsPanel
        break

      case "freeze":
        frozenPlayerIds[targetId] = !frozenPlayerIds[targetId]
        target.innerHTML = `<i data-lucide="snowflake"></i> ${frozenPlayerIds[targetId] ? "Unfreeze" : "Freeze"}`
        lucide.createIcons()
        target.classList.toggle("active")
        postAction("performAdminAction", { targetId, action })

        target.style.transform = "scale(1.05)"
        setTimeout(() => {
          target.style.transform = "scale(1)"
        }, 200)
        break

      case "spectate":
        const currentlySpectatingButton = document.querySelector(`button[data-action="spectate"].active`)
        if (currentlySpectatingButton && currentlySpectatingButton !== target) {
          currentlySpectatingButton.classList.remove("active")
          currentlySpectatingButton.textContent = "Spectate"
        }

        if (spectatingPlayerId === targetId) {
          spectatingPlayerId = null
          target.classList.remove("active")
          target.innerHTML = `<i data-lucide="eye"></i> Spectate`
        } else {
          spectatingPlayerId = targetId
          target.classList.add("active")
          target.innerHTML = `<i data-lucide="eye-off"></i> Stop Spectating`
        }
        lucide.createIcons()
        postAction("performAdminAction", { targetId, action })
        break

      case "giveCar":
        targetIdForCar = targetId
        giveCarModal.classList.remove("hidden")
        carModelInput.focus()

        if (currentOpenMenu) {
          currentOpenMenu.classList.add("hidden")
          currentOpenMenu = null
        }
        break

      default:
        target.style.transform = "scale(0.95)"
        setTimeout(() => {
          target.style.transform = "scale(1)"
        }, 150)

        postAction("performAdminAction", { targetId, action })

        setTimeout(() => {
          actionsPanel.classList.add("hidden")
          currentOpenMenu = null
        }, 300)
        break
    }
  })

  document.addEventListener("click", (e) => {
    if (!e.target.closest(".player-actions") && currentOpenMenu) {
      currentOpenMenu.classList.add("hidden")
      currentOpenMenu = null
    }
  })

  confirmGiveCarBtn.addEventListener("click", () => {
    const model = carModelInput.value.trim()
    if (targetIdForCar && model) {
      confirmGiveCarBtn.textContent = "Giving..."
      confirmGiveCarBtn.disabled = true

      postAction("performAdminAction", { targetId: targetIdForCar, action: "giveCar", model })

      setTimeout(() => {
        giveCarModal.classList.add("hidden")
        carModelInput.value = ""
        targetIdForCar = null
        confirmGiveCarBtn.textContent = "Confirm"
        confirmGiveCarBtn.disabled = false
      }, 500)
    }
  })

  cancelGiveCarBtn.addEventListener("click", () => {
    giveCarModal.classList.add("hidden")
    carModelInput.value = ""
    targetIdForCar = null
  })

  modalCloseBtn.addEventListener("click", () => {
    giveCarModal.classList.add("hidden")
    carModelInput.value = ""
    targetIdForCar = null
  })

  let searchTimeout
  searchBar.addEventListener("input", () => {
    clearTimeout(searchTimeout)
    searchTimeout = setTimeout(() => {
      const filter = searchBar.value.toLowerCase()
      document.querySelectorAll(".player-row").forEach((row) => {
        const isVisible =
          row.dataset.name.includes(filter) || row.dataset.id.includes(filter) || row.dataset.permid.includes(filter)
        row.style.display = isVisible ? "flex" : "none"

        if (!isVisible && currentOpenMenu && row.contains(currentOpenMenu)) {
          currentOpenMenu.classList.add("hidden")
          currentOpenMenu = null
        }
      })
    }, 150)
  })

  closeButton.addEventListener("click", () => postAction("closePanel"))

  window.addEventListener("message", (event) => {
    const data = event.data
    if (data.action === "togglePanel") {
      if (data.show) {
        populatePlayerList(data.players)
        panelContainer.classList.remove("hidden")
        setTimeout(() => {
          panelContainer.style.opacity = "1"
        }, 50)
      } else {
        panelContainer.style.opacity = "0"
        setTimeout(() => {
          panelContainer.classList.add("hidden")
          if (currentOpenMenu) {
            currentOpenMenu.classList.add("hidden")
            currentOpenMenu = null
          }
        }, 300)
      }
    }
  })

  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      if (!giveCarModal.classList.contains("hidden")) {
        cancelGiveCarBtn.click()
      } else if (currentOpenMenu) {
        currentOpenMenu.classList.add("hidden")
        currentOpenMenu = null
      } else if (!panelContainer.classList.contains("hidden")) {
        postAction("closePanel")
      }
    }

    if (e.key === "/" && !giveCarModal.classList.contains("hidden") === false) {
      e.preventDefault()
      searchBar.focus()
    }
  })

  carModelInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") {
      confirmGiveCarBtn.click()
    }
  })
})
