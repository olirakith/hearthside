local MS = _G.MS

MS.L = {}

function MS:SetLocale(localeTable, isFallback)
    if isFallback or GetLocale() == localeTable.locale then
        for key, value in pairs(localeTable.strings) do
            self.L[key] = value
        end
    end
end
