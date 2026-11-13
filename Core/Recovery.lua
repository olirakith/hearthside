local MS = _G.MS

MS.Recovery = { pending = nil, viewportRestoreResult = "NOT_RUN",
    uiParentRestoreResult = "NOT_RUN", workspaceRestoreResult = "NOT_RUN" }

function MS.Recovery:RunOrQueue(action)
    if InCombatLockdown() then
        self.pending = action
        return false
    end
    action()
    return true
end

function MS.Recovery:Restore(reason)
    local runtime = MS.Runtime
    if runtime then
        runtime.restoreAttempts = (runtime.restoreAttempts or 0) + 1
        runtime.restoreHistory = runtime.restoreHistory or {}
        local history = runtime.restoreHistory
        history[#history + 1] = tostring(reason or "unspecified") .. "@" .. tostring(runtime.state)
        if #history > 4 then table.remove(history, 1) end
    end
    if self.restoring or (runtime and runtime.restoring) then return true end
    if runtime and runtime.state == "DISABLED" and not runtime.appliedSteps
        and not (MS.Viewport and MS.Viewport.original)
        and not (MS.UIParentViewport and MS.UIParentViewport:IsApplied()) then
        runtime.closing = false
        return true
    end
    if InCombatLockdown() then
        self:RunOrQueue(function() self:Restore(reason) end)
        return nil, "ERROR_RECOVERY_COMBAT"
    end
    self.restoring = true
    if runtime then
        runtime.restoring, runtime.closing, runtime.state = true, true, "RESTORING"
        runtime.restoreTransactions = (runtime.restoreTransactions or 0) + 1
        runtime.restoreCount = runtime.restoreTransactions -- compatibility with older reports
        runtime.lastRestoreReason = reason or "unspecified"
        runtime.enabled, runtime.enabling = false, false
        runtime.enableGeneration = (runtime.enableGeneration or 0) + 1
    end
    local errors = {}
    local owned = {}
    for _, name in ipairs(runtime and runtime.appliedSteps or {}) do owned[name] = true end
    if MS.Viewport and MS.Viewport.original then owned.viewport = true end
    -- VIEWPORT: UIParent can be established before the runtime records any step.
    if MS.UIParentViewport and MS.UIParentViewport:IsApplied() then owned.uiParent = true end
    local function Step(label, owner, method)
        if not owned[label] then return true end
        if not owner or type(owner[method]) ~= "function" then
            errors[#errors + 1] = label .. ":unavailable"
            return false
        end
        local ok, result, detail = pcall(owner[method], owner)
        if not ok or result == false or (result == nil and detail ~= nil) then
            errors[#errors + 1] = label .. ":" .. tostring(ok and detail or result)
            return false
        end
        return true
    end

    -- Stop Journey and its WORKSPACE tooltip before the workspace is hidden.
    Step("journey", MS.JourneyWorkspace, "Stop")
    Step("tooltip", MS.TooltipBridge, "Restore")
    local viewportRestored = Step("viewport", MS.Viewport, "Restore")
    self.viewportRestoreResult = not owned.viewport and "NOT_OWNED" or (viewportRestored and "PASS" or "FAILED")
    local uiParentRestored = Step("uiParent", MS.UIParentViewport, "Restore")
    self.uiParentRestoreResult = not owned.uiParent and "NOT_OWNED" or (uiParentRestored and "PASS" or "FAILED")
    local workspaceRestored = Step("workspace", MS.Workspace, "Hide")
    self.workspaceRestoreResult = not owned.workspace and "NOT_OWNED" or (workspaceRestored and "PASS" or "FAILED")
    if #errors == 0 then Step("gameRegion", MS.GameUI, "Hide") end
    if MS.Diagnostics then pcall(MS.Diagnostics.RefreshCopyableReportPlacement, MS.Diagnostics) end
    if MS.GameSurfaceContract then pcall(MS.GameSurfaceContract.Refresh, MS.GameSurfaceContract) end
    local success = #errors == 0
    if runtime then
        runtime.lastRestoreResult = success and "PASS" or "FAILED"
        runtime.lastRestoreError = success and "none" or table.concat(errors, ";")
        runtime.state = success and "DISABLED" or "FAILED"
        runtime.appliedSteps = success and nil or runtime.appliedSteps
        runtime.restoring, runtime.closing = false, false
    end
    self.restoring = false
    return success
end

function MS.Recovery:OnCombatEnded()
    local action = self.pending
    self.pending = nil
    if action then
        local ok, err = pcall(action)
        self.deferredResult = ok and "PASS" or "FAILED"
        self.deferredError = ok and "none" or tostring(err)
        if not ok and MS.Diagnostics and MS.L then
            pcall(MS.Diagnostics.Print, MS.Diagnostics,
                string.format(MS.L.RECOVERY_DEFERRED_ERROR, self.deferredError))
        end
    end
end
