using Godot;
using System.Collections.Generic;
using System.Linq;
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;

namespace GodotONNX{
    /// <include file='docs/ONNXInference.xml' path='docs/members[@name="ONNXInference"]/ONNXInference/*'/>
    public class ONNXInference : Node
{
		
	private InferenceSession session;
	/// <summary>
	/// Path to the ONNX model. Use Initialize to change it. 
	/// </summary>
	private string modelPath;
	private int batchSize;

	private SessionOptions SessionOpt;

	//init function
/// <include file='docs/ONNXInference.xml' path='docs/members[@name="ONNXInference"]/Initialize/*'/>
	public void Initialize(string Path, int BatchSize)
	{
		modelPath = Path;
		batchSize = BatchSize;
		SessionConfigurator.SystemCheck();
		SessionOpt = SessionConfigurator.GetSessionOptions();
		session = LoadModel(modelPath);

	}
/// <include file='docs/ONNXInference.xml' path='docs/members[@name="ONNXInference"]/Run/*'/>
	public Godot.Collections.Dictionary<string, Godot.Collections.Array<float>> RunInference(Godot.Collections.Array<float> obs, int state_ins)
	{
		//Current model: Any (Godot Rl Agents)
		//Expects a tensor of shape [batch_size, input_size] type float named obs
		
		//Fill the input tensors
		// create span from inputSize
		var span = new float[obs.Count]; //There's probably a better way to do this
		for (int i = 0; i < obs.Count; i++)
		{
			span[i] = obs[i];
		}
				
		IReadOnlyCollection<NamedOnnxValue> inputs = new List<NamedOnnxValue> 
			{
			NamedOnnxValue.CreateFromTensor("obs", new DenseTensor<float>(span, new int[] { batchSize, obs.Count }))
			}; 
		IReadOnlyCollection<string> outputNames = new List<string> { "output" }; //ONNX is sensible to these names, as well as the input names

			IDisposableReadOnlyCollection<DisposableNamedOnnxValue> results;
		
		try{
			results = session.Run(inputs, outputNames);
		}
		catch (OnnxRuntimeException e) {
			//This error usually means that the model is not compatible with the input, beacause of the input shape (size)
			GD.Print("Error at inference: ", e);
			return null;
		}
		//Can't convert IEnumerable<float> to Variant, so we have to convert it to an array or something
		Godot.Collections.Dictionary<string, Godot.Collections.Array<float>> output = new Godot.Collections.Dictionary<string, Godot.Collections.Array<float>>();
		DisposableNamedOnnxValue output1 = results.First();
		Godot.Collections.Array<float> output1Array = new Godot.Collections.Array<float>();

		foreach (float f in output1.AsEnumerable<float>()) {
			output1Array.Add(f);
		}

		output.Add(output1.Name, output1Array);
		
		//Output is a dictionary of arrays, ex: { "output" : [0.1, 0.2, 0.3, 0.4, ...]}
		return output;
	}	
/// <include file='docs/ONNXInference.xml' path='docs/members[@name="ONNXInference"]/Load/*'/>
	public InferenceSession LoadModel(string Path) 
	{
		// Pass the absolute path directly so ONNXRuntime can resolve external .data files
		var globalPath = ProjectSettings.GlobalizePath(Path);
		return new InferenceSession(globalPath, SessionOpt);
	}
	}
}	
