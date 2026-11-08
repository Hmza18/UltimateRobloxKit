--!strict
-- Every tag behaviour, in binding order: skinning and structure first, then panels, buttons,
-- bindings and overlays. Each module exposes `tags` and `bind(context, tag, instance, trove, values)`.

return {
	require("./Visual"),
	require("./Structure"),
	require("./Panel"),
	require("./Button"),
	require("./Bind"),
	require("./Tabs"),
	require("./Overlay"),
	require("./DragDrop"),
}
