for pname, port in pairs(manager.machine.ioport.ports) do
  for fname, field in pairs(port.fields) do
    print(string.format("PORT %s FIELD %-24s mask=%04x", pname, fname, field.mask))
  end
end
manager.machine:exit()
