# UVM extension agent class

*Chapter: UVM extension library · source: attached*

Hi my name is Cristian Slav and in this tutorial we are going to code together the UVM extension agent class.
First, we are going to declare this class with the right parameters and then we are going to move all that API from our APB agent and after that we will adapt also the MD agent to inherit from this UVM extension agent.
And after that we will update our UVM extension package so that the agent can be configured via the UVM configuration database.
And we will do this for our TX agent, but in the same time we will keep the old configuration mechanism for our RX agent and for our APB agent.
The starting point is the "UVM Extension Agent - Practice" project from EDA Playground, which, as always, we need to copy and let's resize the window.
The first thing that we have to do is to create the UVM extension agent file and include it in our UVM extension package.
Now let's declare the UVM extension agent class with the right parameters So remember that we need to define the type of the virtual interface, the type of the item used by the monitor, and the type of the item used by the driver.
So let's do this.
Now let's go to our APB agent and try to move some of the API from there.
So we can take the handlers of the components declared under the agent.
So these would be agent_config, driver, sequencer, monitor and coverage.
So let's copy this code from here.
And here, let's fix the types of these handlers.
Here in the APB agent, let's comment the declaration of these handlers.
And let's take completely the build_phase() and move it to our UVM extension agent.
And let's fix the types used here.
From the APB agent, let's also take the connect_phase() completely.
And let's fix the types.
That's it.
And we can take the rest of the functions and tasks so we can take wait_reset_start(), wait_reset_end(), handle_ reset() and also run_phase(). handle_ reset() and also run_phase().
And now in the APB package, let's declare the overrides and we can do this in the constructor, so we can override the types of each of those handlers declared under the UVM extension agent with the correct types used by the APB agent.
So let's do this.
So here we override the UVM extension agent config with this type here, so we can remove this one and let's do the same for the rest of the handlers.
And for the sequencer, we don't need to do an override as we don't have a specific sequencer for the APB agent.
And now let's fix the parent used by the cfs_apb_agent class.
That's it.
Now the only remaining thing is to fix the connection that we had for the pointer of the agent_config in our APB classes.
So let's search for that code which we set at some point.
It is a temporary code.
Here, so up until now we actually used to connect the agent_config pointer from the parent class to this one from here.
But now we need to reverse this connection to connect this one to this one.
So let's do this.
So let's clarify again this.
Now with our UVM extension agent class, this super.agent_config is created in the parent class.
So we need to connect this pointer here which is no longer assigned by anybody else and connect it to this super.agent_config.
And we need to do the casting because in the parent class this agent_config is of type uvm_ext_agent_config, not of this type.
This is why we need to do the casting here.
So we can remove this code from here and do the same in two other places in our agent.
So we need to do it here.
And also here.
That's it.
Now let's try to run to see if our code compiles and runs correctly, with our entire APB agent inheriting correctly from the UVM extension package.
OK, the simulation finished and let's look on the log.
So the log looks OK, we don't have any errors and it seems that the simulation run OK.
So we managed to implement correctly the UVM extension agent and use it in our APB agent and now let's do the same thing for our MD agent.
So let's go to our MD package and go down to our agent.
Here, let's remove the handlers.
Let's remove the rest of the functions. build_phase(), connect_phase(), wait_reset_start(), wait_reset_end(), handle_reset() and run_phase().
Now in the constructor, let's declare the overrides just like we did for the APB.
So let's try to copy paste the code from there.
And place it here.
And let's be very careful not to do some copy paste error here.
And remember, in the MD agent we do have a class for the sequencer, so let's overwrite also that one and it is called cfs_md_sequencer_base.
Now let's fix the parent class of our cfs_md_agent.
And now let's fix that connection to our agent_config.
And let's take this code and put it in two other places.
Here.
End here.
That's it.
Now let's try to run to see if our project runs correctly, with both of our agents inheriting completely from our UVM extension package.
The simulation finished and when we look on the log we have no errors and the log looks OK.
We get all the messages from our monitors and drivers.
So we managed to implement correctly our UVM extension agent and now let's try to implement that update that we talked about regarding the configuration of our agent.
Let's update our UVM extension package so that the agent can be configured via the UVM configuration database.
And we will do this for our TX agent, but the rest of the agents will be configured in the same way as they are now.
So let's do this.
First we need to go to the UVM extension agent, in its build_phase().
Here, the agent_config is created no matter what, but what we can do is to create the agent_config only if it is not available in the database.
So let's do this.
And that's it.
That's the entire code that we need to implement in our UVM extension agent to support both of these configuration modes.
If the agent configuration class is in the database, then we use that one.
Otherwise we will create our agent_config here.
And now let's configure only the TX agent to use the agent configuration instance from the database.
And we can do this from our environment here where we create the agents just before the creation of the MD TX agent, we can create the agent configuration instance and put it in the database so that this agent will be able to take it from there.
That's it.
We created here the instance of our agent_config and now let's put it in the database.
And let's explain the code a little bit.
In the database when we put this agent_config, we need to specify the type used by the UVM extension agent to get from the database the agent_config which is this one.
And then we put the instance of this agent_config to be available only for our MD TX agent, so this string here should correspond with this one, and we put it with the name "agent_config" just like our agent will try to take it.
And then we passed the instance.
Now let's try to run to see if our simulation runs correctly with this new code added.
That's it, the simulation finished and let's also try to add some signals on the waveforms.
So everything looks good on the waveforms.
Let's zoom a little bit and let's also look on the log.
We have no errors and what I want to change for our TX agent is the stuck threshold.
Let's change only for this agent the stuck threshold to a really small value, let's say 3, so that the agent will consider that this access from here, which is longer than 3 clock cycles from valid from here until ready here it's more than 3 clock cycles, so let's set it to 3 so that our agent will complain that this access here is stuck.
So let's do this.
And now let's try to run again.
That's it.
So it looks like the simulation finished here during the first access on the TX interface.
And if we look on the log we should see the error here coming from our TX agent saying that the MD transfer reached the stuck threshold.
So this new configuration mechanism work for us and this is what you will also see in real projects.
So just before the creation of the agent you will see some code which will create the agent configuration class, will configure all the fields here and then put it in the database.
And usually as I told you, this is done for all the agents.
But now we have both of these approaches that we can use, so we are more flexible with our UVM extension agent.
But now let's fix the code and set this stuck threshold to a bigger value, let's say 100 and run again the simulation to see if everything is OK.
OK, our simulation finished and this time we did not receive any errors from our agent.
So everything run correctly as expected.
So that's it for this tutorial.
We managed to implement also the last class in our UVM extension package, the agent.
And we also updated the configuration mechanism so that we can configure an agent by putting the agent configuration class in the database and creating that instance of the agent configuration class at a higher level in our environment.
That's it for this tutorial.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye.
