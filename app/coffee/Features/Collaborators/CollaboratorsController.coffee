ProjectGetter = require "../Project/ProjectGetter"
CollaboratorsHandler = require "./CollaboratorsHandler"
CollaboratorsEmailHandler = require "./CollaboratorsEmailHandler"
ProjectEditorHandler = require "../Project/ProjectEditorHandler"
EditorRealTimeController = require "../Editor/EditorRealTimeController"
UserGetter = require "../User/UserGetter"
LimitationsManager = require "../Subscription/LimitationsManager"
ContactManager = require "../Contacts/ContactManager"
mimelib = require("mimelib")

module.exports = CollaboratorsController =
	getCollaborators: (req, res, next = (error) ->) ->
		ProjectGetter.getProject req.params.Project_id, { owner_ref: true, collaberator_refs: true, readOnly_refs: true}, (error, project) ->
			return next(error) if error?
			ProjectGetter.populateProjectWithUsers project, (error, project) ->
				return next(error) if error?
				CollaboratorsController._formatCollaborators project, (error, collaborators) ->
					return next(error) if error?
					res.send(JSON.stringify(collaborators))
			
	addUserToProject: (req, res, next) ->
		project_id = req.params.Project_id
		LimitationsManager.isCollaboratorLimitReached project_id, (error, limit_reached) =>
			return next(error) if error?

			if limit_reached
				return res.json { user: false }
			else
				{email, privileges} = req.body
				
				email = mimelib.parseAddresses(email or "")[0]?.address?.toLowerCase()
				if !email? or email == ""
					return res.status(400).send("invalid email address")
					
				CollaboratorsHandler.addEmailToProject project_id, email, privileges, (error, user_id) =>
					return next(error) if error?
					UserGetter.getUser user_id, (error, raw_user) ->
						return next(error) if error?
						user = ProjectEditorHandler.buildUserModelView(raw_user, privileges)
						
						# These things can all be done in the background
						adding_user_id = req.session?.user?._id
						CollaboratorsEmailHandler.notifyUserOfProjectShare project_id, user.email
						EditorRealTimeController.emitToRoom(project_id, 'userAddedToProject', user, privileges)
						ContactManager.addContact adding_user_id, user_id

						return res.json { user: user }

	removeUserFromProject: (req, res, next) ->
		project_id = req.params.Project_id
		user_id    = req.params.user_id
		CollaboratorsController._removeUserIdFromProject project_id, user_id, (error) ->
			return next(error) if error?
			res.sendStatus 204
	
	removeSelfFromProject: (req, res, next = (error) ->) ->
		project_id = req.params.Project_id
		user_id    = req.session?.user?._id
		CollaboratorsController._removeUserIdFromProject project_id, user_id, (error) ->
			return next(error) if error?
			res.sendStatus 204

	_removeUserIdFromProject: (project_id, user_id, callback = (error) ->) ->
		CollaboratorsHandler.removeUserFromProject project_id, user_id, (error)->
			return callback(error) if error?
			EditorRealTimeController.emitToRoom(project_id, 'userRemovedFromProject', user_id)
			callback()

	_formatCollaborators: (project, callback = (error, collaborators) ->) ->
		collaborators = []

		pushCollaborator = (user, permissions, owner) ->
			collaborators.push {
				id: user._id.toString()
				first_name: user.first_name
				last_name: user.last_name
				email: user.email
				permissions: permissions
				owner: owner
			}
			
		if project.owner_ref?
			pushCollaborator(project.owner_ref, ["read", "write", "admin"], true)

		if project.collaberator_refs? and project.collaberator_refs.length > 0
			for user in project.collaberator_refs
				pushCollaborator(user, ["read", "write"], false)

		if project.readOnly_refs? and project.readOnly_refs.length > 0
			for user in project.readOnly_refs
				pushCollaborator(user, ["read"], false)

		callback null, collaborators
			
