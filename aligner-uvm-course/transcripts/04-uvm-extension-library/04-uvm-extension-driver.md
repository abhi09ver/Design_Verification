# UVM extension driver

*Chapter: UVM extension library · source: attached*

Hi my name is Cristian Slav and in this tutorial we are going to code together the UVM extension driver.
First we are going to move some of the API from our APB driver to our UVM extension driver, this API here.
And then we will adapt the MD driver to inherit from our UVM extension driver.
The starting point is the UVM Extension Driver - Practice project from EDA Playground, which we need to copy.
And now let's resize the windows to make more room.
First, let's create the UVM extension driver file and then declare the class.
That's it.
Now let's include this file.
Now let's declare the same agent_config pointer just like we declared in the monitor.
This code here.
And now let's start to move here some of the code from the APB driver.
We can take the pointer to the process of drive_transactions() task.
We can take the run_phase() task as it has nothing to do with the protocol implemented.
Let's take the drive_transaction() task and declare it in our UVM extension driver and just put a fatal message to remind us to implement this task.
We can also take drive_transactions() task just like it is and also wait_reset_end().
And we should fix the type of the item we used here, it should not be the APB item drive.
And also here, it should be the parameter of our class, this one.
From the handle_reset() function, we can take this code and place it in the UVM extension driver as this is generic.
But the rest of the code which initialize the APB signals must stay here in the APB driver.
So let's do this.
So we don't need here the pointer to the interface.
And also this part here.
But now in the APB driver we should call the super implementation of this handle_reset().
And we should get rid of this code because this is the job of the handle_reset() implementation from the parent class.
Now let's fix the parent class of our APB driver.
And now we only need to connect the agent_config pointer from here to the one from the parent class.
And for this we have that end_of_elaboration_phase() function, this one here.
That's it.
Now let's see if our code compiles and runs correctly with our APB driver inheriting from the UVM extension driver.
The simulation finished, but it looks like we have an error and this one is an assertion.
And let's look through the log to see exactly what is the problem.
And the problem is here reported at the beginning of the simulation saying that the PSEL signal has an unknown value.
And there is a very simple explanation for this one.
Now that our APB driver is inheriting from the UVM extension driver, it is actually implementing the UVM extension handle reset.
But if we look in the APB package at the agent part.
We can see that the handle_reset() implementation from the APB agent is only resetting the components which are implementing the cfs_apb_reset_handler So we need to fix this.
We need to get rid of this interface class and replace it completely with our uvm_ext_reset_handler.
So let's do this.
We can get rid of the declaration.
Here we must replace it with uvm_ext_reset_handler.
And also here.
And now let's try to run and see if this will fix our error.
The simulation finished and we no longer have that error reported also here at the end of the simulation and if we look through the log, everything is OK, including at the beginning of the simulation.
We no longer have that assertion here.
So now the APB driver inherits correctly from the UVM extension driver and everything works OK.
And now let's adapt the MD driver to also inherit from our UVM extension driver.
Let's take this in order to fix the parent class of our MD driver.
And we can remove the code which is already implemented in the parent class so we can remove the process to drive_transactions().
We can remove the run_phase(). drive_transaction() is already declared in the parent class and here has no implementation, so we can remove this one.
Also drive_transactions() and wait_reset_end() drive_transactions() and wait_reset_end() And finally handle_reset().
We can also get rid of it.
And let's take that end_of_elaboration_phase() function.
And let's get rid of that cfs_md_reset_handler.
Let's get rid of the declaration.
Here we should replace it with uvm_ext_reset_handler.
And also here.
That's it.
Now let's try to run and see if our code runs correctly, with both of our drivers inheriting from the UVM extension driver.
The simulation finished, we have no errors in our log and everything looks good if we look through the log.
So we managed to implement correctly our UVM extension driver and use it in both of our packages.
That's it for this tutorial.
I hope everything was clear for you.
Thanks for watching and see you in the next tutorial.
Bye.
