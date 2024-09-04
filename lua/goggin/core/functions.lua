function IsDelavieMediaProject()
    if vim.fn.expand("%:p:h"):find("DelavieMedia") then
        return true
    else
        return false
    end
end
