//! Abstractions for creating an ONNX Runtime Session and Environment which can be safely
//! passed to and from the BEAM.
//!
//! # Examples
//!
//! ```
//! let model = init("./models/resnet50.onnx", vec![])?;
//! let (inputs, outputs) = show(model)?;
//! ```

use crate::tensor::OrtexTensor;
use crate::utils::{is_bool_input, map_opt_level};
use std::convert::TryInto;
use std::ffi::CStr;
use std::iter::zip;

use ort::execution_providers::ExecutionProviderDispatch;
use ort::session::builder::SessionBuilder;
use ort::session::{Session, SessionInputValue};
use ort::{AsPointer, Error};
use rustler::resource::ResourceArc;
use rustler::Atom;

/// Holds the model state which include onnxruntime session and environment. All
/// are threadsafe so this can be called concurrently from the beam.
pub struct OrtexModel {
    pub session: Session,
}

// Since we're only using the session for inference and
// inference is threadsafe, this Sync is safe. Additionally,
// Environment is global and also threadsafe
// https://github.com/microsoft/onnxruntime/issues/114
unsafe impl Sync for OrtexModel {}

/// Creates a model given the path to the model and vector of execution providers.
/// The execution providers are Atoms from Erlang/Elixir.
pub fn init(
    model_path: String,
    eps: Vec<ExecutionProviderDispatch>,
    opt: i32,
) -> Result<OrtexModel, Error> {
    // TODO: send tracing logs to erlang/elixir _somehow_
    // tracing_subscriber::fmt::init();

    let session = Session::builder()?
        .with_optimization_level(map_opt_level(opt))?
        .with_execution_providers(eps)?
        .commit_from_file(model_path)?;

    let state = OrtexModel { session };
    Ok(state)
}

/// Creates a model with provider-specific options and optional ONNX Runtime profiling.
pub fn init_with_options(
    model_path: String,
    providers: Vec<(String, Vec<(String, String)>)>,
    opt: i32,
    profile_prefix: Option<String>,
) -> Result<OrtexModel, Error> {
    let mut builder = Session::builder()?.with_optimization_level(map_opt_level(opt))?;

    for (provider, options) in providers {
        match provider.as_str() {
            "cpu" => {}
            "coreml" => register_coreml(&mut builder, options)?,
            other => {
                return Err(Error::new(format!(
                    "unsupported structured execution provider: {other}"
                )))
            }
        }
    }

    if let Some(prefix) = profile_prefix {
        builder = builder.with_profiling(prefix)?;
    }

    let session = builder.commit_from_file(model_path)?;
    Ok(OrtexModel { session })
}

#[cfg(target_os = "macos")]
extern "C" {
    fn OrtSessionOptionsAppendExecutionProvider_CoreML(
        options: *mut ort::sys::OrtSessionOptions,
        flags: u32,
    ) -> ort::sys::OrtStatusPtr;
}

fn register_coreml(
    builder: &mut SessionBuilder,
    options: Vec<(String, String)>,
) -> Result<(), Error> {
    #[cfg(target_os = "macos")]
    {
        let flags = coreml_flags(options)?;
        let status =
            unsafe { OrtSessionOptionsAppendExecutionProvider_CoreML(builder.ptr_mut(), flags) };
        return status_to_result(status);
    }

    #[cfg(not(target_os = "macos"))]
    {
        let _ = (builder, options);
        Err(Error::new("CoreML is only available on Apple platforms"))
    }
}

fn coreml_flags(options: Vec<(String, String)>) -> Result<u32, Error> {
    options.into_iter().try_fold(0_u32, |flags, option| {
        let flag = match option {
            (key, value) if key == "ModelFormat" && value == "MLProgram" => 0x010,
            (key, value) if key == "ModelFormat" && value == "NeuralNetwork" => 0,
            (key, value) if key == "MLComputeUnits" && value == "ALL" => 0,
            (key, value) if key == "MLComputeUnits" && value == "CPUOnly" => 0x001,
            (key, value) if key == "MLComputeUnits" && value == "CPUAndGPU" => 0x020,
            (key, value) if key == "MLComputeUnits" && value == "CPUAndNeuralEngine" => 0x004,
            (key, value) if key == "RequireStaticInputShapes" && value == "1" => 0x008,
            (key, value) if key == "RequireStaticInputShapes" && value == "0" => 0,
            (key, value) if key == "EnableOnSubgraphs" && value == "1" => 0x002,
            (key, value) if key == "EnableOnSubgraphs" && value == "0" => 0,
            other => return Err(Error::new(format!("unsupported CoreML option: {other:?}"))),
        };

        Ok(flags | flag)
    })
}

fn status_to_result(status: *mut ort::sys::OrtStatus) -> Result<(), Error> {
    if status.is_null() {
        return Ok(());
    }

    let api = ort::api();
    let message = unsafe {
        let get_message = api
            .GetErrorMessage
            .expect("ONNX Runtime error-message API is available");
        CStr::from_ptr(get_message(status))
            .to_string_lossy()
            .into_owned()
    };

    unsafe {
        let release = api
            .ReleaseStatus
            .expect("ONNX Runtime status-release API is available");
        release(status);
    }

    Err(Error::new(message))
}

/// Flushes the profiling trace and returns its generated path.
pub fn end_profiling(model: ResourceArc<OrtexModel>) -> Result<String, Error> {
    model.session.end_profiling()
}

/// Returns input/output information about a model. The result is a Tuple of
/// `inputs` and `outputs` with elements of `(Name, Type, Dimension)` where
/// `Dimension` elements of -1 are dynamic.
pub fn show(
    model: ResourceArc<OrtexModel>,
) -> (
    Vec<(String, String, Option<Vec<i64>>)>,
    Vec<(String, String, Option<Vec<i64>>)>,
) {
    let model: &OrtexModel = &*model;

    let mut inputs = Vec::new();
    for input in model.session.inputs.iter() {
        let name = input.name.to_string();
        let repr = format!("{:#?}", input.input_type);
        let dims = Option::<&Vec<i64>>::cloned(input.input_type.tensor_dimensions());
        inputs.push((name, repr, dims));
    }

    let mut outputs = Vec::new();
    for output in model.session.outputs.iter() {
        let name = output.name.to_string();
        let repr = format!("{:#?}", output.output_type);
        let dims = Option::<&Vec<i64>>::cloned(output.output_type.tensor_dimensions());
        outputs.push((name, repr, dims));
    }

    (inputs, outputs)
}

/// Runs the model with the given inputs. Returns a vector of tensors. Use `model::show`
/// to see what the model expects for input and output shapes.
pub fn run(
    model: ResourceArc<OrtexModel>,
    inputs: Vec<ResourceArc<OrtexTensor>>,
) -> Result<Vec<(ResourceArc<OrtexTensor>, Vec<usize>, Atom, usize)>, Error> {
    // Grab the session and run a forward pass with it
    let session: &Session = &model.session;

    let mut ortified_inputs: Vec<SessionInputValue> = Vec::new();

    for (elixir_input, onnx_input) in zip(inputs, &session.inputs) {
        let derefed_input: &OrtexTensor = &elixir_input;
        if is_bool_input(&onnx_input.input_type) {
            // this assumes that the boolean input isn't huge -- we're cloning it twice;
            // once below, once in the try_into()
            let boolified_input: &OrtexTensor = &derefed_input.clone().to_bool();
            let v: SessionInputValue = boolified_input.try_into()?;
            ortified_inputs.push(v);
        } else {
            let v: SessionInputValue = derefed_input.try_into()?;
            ortified_inputs.push(v);
        }
    }

    // Construct a Vec of ModelOutput enums based on the DynOrtTensor data type
    let outputs = session.run(&ortified_inputs[..])?;
    let mut collected_outputs = Vec::new();

    for output_descriptor in &session.outputs {
        let output_name: &str = &output_descriptor.name;
        let val = outputs.get(output_name).expect(
            &format!(
                "Expected {} to be in the outputs, but didn't find it",
                output_name
            )[..],
        );

        // NOTE: try_into impl here will implicitly map bool outputs to u8 outputs
        let ortextensor: OrtexTensor = val.try_into()?;
        let shape = ortextensor.shape();
        let (dtype, bits) = ortextensor.dtype();

        let collected_output = (ResourceArc::new(ortextensor), shape, dtype, bits);
        collected_outputs.push(collected_output)
    }

    Ok(collected_outputs)
}
